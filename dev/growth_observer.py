"""Read-only TapTap observations. Never treats PV/devices as unique players.

Uses the installed official CLI, not private HTTP endpoints. No publishing,
messages, credential discovery, or scheduled jobs are performed by this tool.
"""
import argparse
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time

CHINA = timezone(timedelta(hours=8))
PLAYER_GOAL = 100_000
METRICS = ('mini_device', 'mini_ret', 'mini_duration', 'mini_conversion', 'pv', 'launcher_button', 'position')
TOPICS = {
    'stability': ('闪退', '黑屏', '卡死', '进不去', '无法进入'),
    'mobile_interface': ('手机', '界面', '按钮', '触屏', '适配'),
    'onboarding': ('看不懂', '不会玩', '教程', '怎么玩', '操作说明'),
    'pacing': ('无聊', '重复', '太慢', '太难', '太简单'),
}


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def count(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if not math.isfinite(value) or value < 0 or value != int(value):
        return None
    return int(value)


def business(envelope):
    if envelope.get('ok') is not True:
        return None
    result = envelope.get('data', {}).get('result')
    if not isinstance(result, dict) or result.get('in_error') is True:
        return None
    return result


def daily_counts(envelope, key, start, end):
    """Unknown, explicit zero, and incomplete coverage remain distinct."""
    result = business(envelope)
    expected = {(start + timedelta(days=i)).isoformat() for i in range((end-start).days+1)}
    if result is None or not isinstance(result.get('series'), list):
        return {'status': 'unavailable', 'known_sum': None, 'days': {}, 'missing_dates': sorted(expected)}
    points, invalid, seen = {}, [], set()
    for row in result['series']:
        stamp = row.get('timestamp')
        if stamp not in expected or stamp in seen:
            invalid.append(str(stamp))
            continue
        seen.add(stamp)
        value = count(row.get('values', {}).get(key))
        if value is not None:
            points[stamp] = value
    if invalid:
        return {'status': 'invalid_series', 'known_sum': None, 'days': {}, 'invalid_dates': invalid,
                'missing_dates': sorted(expected)}
    missing = sorted(expected - points.keys())
    return {'status': 'complete' if not missing else 'partial',
            'known_sum': sum(points.values()) if points else None,
            'days': points, 'missing_dates': missing}


def retention(envelope, devices, lag, observed_day, end):
    """A cohort needs its entire retention day to have elapsed, plus data."""
    result = business(envelope)
    if result is None or not isinstance(result.get('series'), list):
        return {'status': 'unavailable', 'mature_cohorts': [], 'immature_cohorts': [],
                'missing_mature_cohorts': [], 'mature_new_devices': 0, 'all_mature_zero': None}
    rows = {}
    for row in result['series']:
        stamp = row.get('timestamp')
        if stamp in rows:
            return {'status': 'invalid_series', 'all_mature_zero': None, 'mature_cohorts': []}
        rows[stamp] = row.get('values', {})
    last_complete = min(observed_day - timedelta(days=1), end)
    key = f'ret_new_active_device_rate_a{lag}d'
    mature, immature, missing = [], [], []
    for stamp, new_devices in devices.get('days', {}).items():
        if new_devices <= 0:
            continue
        cohort = {'date': stamp, 'new_devices': new_devices}
        if date.fromisoformat(stamp) + timedelta(days=lag) > last_complete:
            immature.append(cohort)
            continue
        value = rows.get(stamp, {}).get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            missing.append(cohort)
        else:
            mature.append({**cohort, 'raw_rate': value})
    zero = all(x['raw_rate'] == 0 for x in mature) if mature and not missing and devices['status'] == 'complete' else None
    status = 'partial' if missing or devices['status'] != 'complete' else 'complete'
    if status == 'complete' and not mature:
        status = 'not_mature' if immature else 'no_new_devices'
    return {'status': status,
            'mature_cohorts': mature, 'immature_cohorts': immature, 'missing_mature_cohorts': missing,
            'mature_new_devices': sum(x['new_devices'] for x in mature), 'all_mature_zero': zero,
            'rate_unit': 'platform_raw; do not infer a nonzero percentage scale'}


def review_evidence(envelopes, complete):
    by_id, invalid = {}, 0
    for envelope in envelopes:
        result = business(envelope)
        if result is None or not isinstance(result.get('list'), list):
            invalid += 1
            continue
        for item in result['list']:
            review_id = item.get('review_id')
            if review_id is None:
                invalid += 1
                continue
            by_id[review_id] = item
    topics = {key: [] for key in TOPICS}
    for item in by_id.values():
        body = item.get('contents', '')
        if not isinstance(body, str):
            continue
        for topic, words in TOPICS.items():
            if any(word in body for word in words):
                topics[topic].append({'score': item.get('score'), 'excerpt': body[:160],
                                      'url': item.get('url'), 'updated_time': item.get('updated_time')})
    return {'returned_unique_reviews': len(by_id), 'complete_scan': bool(complete and not invalid),
            'invalid_records_or_pages': invalid, 'topics': topics,
            'interpretation': 'Keyword routing is an agent assessment; matching positive feedback is not a negative review.'}


def version_evidence(envelope):
    result = business(envelope)
    if result is None or not isinstance(result.get('list'), list):
        return {'status': 'unavailable', 'latest_online': None, 'pending': []}
    items = result['list']
    total = count(result.get('total'))
    if total is None or len(items) < total:
        return {'status': 'partial', 'latest_online': None, 'pending': []}
    online = [x for x in items if x.get('status') == 'online']
    dated = [x for x in online if count(x.get('created_time')) is not None]
    latest = max(dated, key=lambda x: x['created_time']).get('version') if len(dated) == len(online) and dated else None
    pending = [{'version': x.get('version'), 'status': x.get('status')}
               for x in items if x.get('status') in ('draft', 'reviewing', 'scheduled', 'rejected')]
    return {'status': 'complete', 'latest_online': latest, 'pending': pending,
            'scope': 'Version state only; CLI does not map source commits to the statistics.'}


def store_traffic(result, total):
    if result is None or total is None:
        return {'status': 'unavailable', 'sources': []}
    values = result.get('summary', {}).get('values', {})
    sources = []
    for column in result.get('columns', []):
        key = column['key']
        if key == 'pv_from_total':
            continue
        pv = count(values.get(key))
        if pv is None:
            return {'status': 'incomplete', 'sources': []}
        sources.append({'key': key, 'label': column.get('label') or key, 'pv': pv})
    if not sources:
        return {'status': 'unavailable', 'sources': []}
    if sum(row['pv'] for row in sources) != total:
        return {'status': 'inconsistent', 'sources': []}
    return {'status': 'complete', 'sources': sorted(sources, key=lambda row: (-row['pv'], row['key']))}


def analyze(responses, start, end, observed_day, review_scan_complete=True):
    devices = daily_counts(responses.get('mini_device', {}), 'new_active_device_num', start, end)
    pv_result = business(responses.get('pv', {}))
    pv = count(pv_result.get('summary', {}).get('values', {}).get('pv_from_total')) if pv_result else None
    if pv is None:
        points = daily_counts(responses.get('pv', {}), 'pv_from_total', start, end)
        pv = points['known_sum'] if points['status'] == 'complete' else None
    reviews = review_evidence(responses.get('reviews', []), review_scan_complete)
    forum = business(responses.get('forum', {})) or {}
    forum_posts = forum.get('list')
    releases = version_evidence(responses.get('versions', {}))
    unavailable = [key for key in METRICS if business(responses.get(key, {})) is None]
    decisions = []
    if releases['pending']:
        decisions.append({'priority': 'release', 'action': '存在尚未发布的版本，先核对其测试/审核状态；当前全版本统计不能视为该版的改进效果。',
                          'evidence': releases['pending'], 'source': 'current_fact'})
    if unavailable or devices['status'] != 'complete':
        decisions.append({'priority': 'data', 'action': '补齐缺失数据；不要把查询失败或缺少日期当作零。',
                          'evidence': unavailable or devices['missing_dates'], 'source': 'current_fact'})
    if reviews['topics']['stability']:
        decisions.append({'priority': 'P0', 'action': '复现玩家报告的稳定性问题；未复现前保留原文与影响范围。',
                          'evidence': reviews['topics']['stability'], 'source': 'agent_assessment'})
    if reviews['topics']['mobile_interface']:
        decisions.append({'priority': 'P1', 'action': '核对已完成的手机修复是否已发布，再用真实设备和后续反馈验证，避免重复开发。',
                          'evidence': reviews['topics']['mobile_interface'], 'source': 'agent_assessment'})
    d1 = retention(responses.get('mini_ret', {}), devices, 1, observed_day, end)
    if d1.get('all_mature_zero') is True:
        decisions.append({'priority': 'P1', 'action': '成熟小样本批次的留存原值均为零；检查首局理解、首次购物与复玩动机，不作因果判断。',
                          'evidence': d1['mature_cohorts'], 'source': 'agent_assessment'})
    if reviews['topics']['onboarding'] or reviews['topics']['pacing']:
        decisions.append({'priority': 'P1', 'action': '将新手理解与节奏反馈转成可复现场景，优先验证问题，再决定玩法改动。',
                          'evidence': reviews['topics']['onboarding'] + reviews['topics']['pacing'], 'source': 'agent_assessment'})
    duration = business(responses.get('mini_duration', {}))
    position = business(responses.get('position', {})) or {}
    position_summary = position.get('summary', {}).get('values', {})
    return {'scope': 'App aggregate across all versions; no version attribution',
            'period': {'start': start.isoformat(), 'end': end.isoformat(), 'observed_day': observed_day.isoformat()},
            'new_devices': devices, 'store_pv': pv, 'store_traffic': store_traffic(pv_result, pv), 'd1': d1,
            'store_position': {'impressions': count(position_summary.get('impression_cnt')),
                               'clicks': count(position_summary.get('click_cnt')),
                               'detail_conversions': count(position_summary.get('convert_detail_cnt'))},
            'd3': retention(responses.get('mini_ret', {}), devices, 3, observed_day, end),
            'd7': retention(responses.get('mini_ret', {}), devices, 7, observed_day, end),
            'duration': {'status': 'available_raw' if duration else 'unavailable',
                         'server_highlights': duration.get('highlights', []) if duration else [],
                         'unit': 'unverified: min in field name conflicts with seconds in bundled cheatsheet'},
            'reviews': reviews,
            'forum': {'total_visible_posts': count(forum.get('total')),
                      'latest_posts': [{'title': post.get('title'), 'url': post.get('url'),
                                        'comments': count((post.get('stat') or {}).get('comments'))}
                                       for post in forum_posts] if isinstance(forum_posts, list) else None},
            'release_state': releases, 'unavailable_metrics': unavailable, 'decisions': decisions,
            'goal_evidence': {'cumulative_unique_actual_players': None, 'exclusive_target': PLAYER_GOAL, 'target_verified': False,
                              'reason': 'Daily device counts and store PV do not prove lifetime unique actual players.'}}


class Reader:
    def __init__(self, node, cli, developer, app, out, cache, refresh=False):
        self.node, self.cli = node, cli
        self.scope = ['--dev-id', str(developer), '--app-id', str(app)]
        self.out, self.cache, self.refresh = out, cache, refresh
        self.last_request = 0.0
        self.manifest = []

    def invoke(self, args):
        delay = 0.4 - (time.monotonic() - self.last_request)
        if delay > 0:
            time.sleep(delay)
        self.last_request = time.monotonic()
        try:
            proc = subprocess.run([self.node, str(self.cli), *args], capture_output=True, timeout=65)
            value = json.loads((proc.stdout or proc.stderr).decode('utf-8-sig'))
            if not isinstance(value, dict) or 'ok' not in value:
                raise ValueError('Missing CLI envelope')
            if proc.returncode and value.get('ok'):
                return {'ok': False, 'error': {'type': 'transport', 'message': 'CLI exit status contradicted success'}}
            return value
        except (subprocess.TimeoutExpired, ValueError, OSError, UnicodeError) as error:
            return {'ok': False, 'error': {'type': type(error).__name__, 'message': str(error)[:200]}}

    def read(self, name, service, operation, payload=None, extra=(), ttl=900):
        args = [service, operation, *self.scope]
        if payload is not None:
            args += ['--data', json.dumps(payload, ensure_ascii=False)]
        args += list(extra)
        key = hashlib.sha256(json.dumps(args, ensure_ascii=True).encode()).hexdigest()
        cache_path = self.cache / (key + '.json')
        now = datetime.now(timezone.utc)
        cached = False
        fetched_at = now.isoformat()
        value = None
        if not self.refresh and cache_path.exists():
            try:
                entry = load(cache_path)
                age = (now - datetime.fromisoformat(entry['fetched_at'])).total_seconds()
                if 0 <= age < ttl and business(entry['envelope']) is not None:
                    value, fetched_at, cached = entry['envelope'], entry['fetched_at'], True
            except (ValueError, KeyError, TypeError, OSError):
                pass
        attempts = 0
        if value is None:
            for attempts in (1, 2):
                value = self.invoke(args)
                error = value.get('error', {})
                retry = error.get('retryable') is True and error.get('code') in (429, 500, 502, 503, 504)
                if not retry or attempts == 2:
                    break
                time.sleep(2)
            fetched_at = datetime.now(timezone.utc).isoformat()
            if business(value) is not None:
                save(cache_path, {'fetched_at': fetched_at, 'envelope': value})
        save(self.out / (name + '.json'), value)
        self.manifest.append({'name': name, 'operation': [service, operation], 'payload': payload,
                              'cached': cached, 'fetched_at': fetched_at, 'attempts': attempts,
                              'sha256': hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest(),
                              'ok': business(value) is not None})
        print(json.dumps({'query': name, 'ok': business(value) is not None, 'cached': cached}), flush=True)
        return value


def markdown(report):
    n = report['new_devices']
    devices = str(n['known_sum']) if n['known_sum'] is not None else '未知'
    if n['status'] != 'complete':
        devices += '（仅已返回日期，非完整区间合计）'
    pv = str(report['store_pv']) if report['store_pv'] is not None else '未知'
    position = {key: '未知' if value is None else str(value) for key, value in report['store_position'].items()}
    forum = report['forum']
    forum_scope = (f"可见帖子共 {forum['total_visible_posts']} 条，本次读取最新 {len(forum['latest_posts'])} 条。"
                   if forum['total_visible_posts'] is not None and forum['latest_posts'] is not None else '本次未取得完整列表统计。')
    lines = ['# 暗影幸存者数据观察', '',
             f"统计范围：{report['period']['start']} 至 {report['period']['end']}；{report['period']['observed_day']} 读取。",
             '口径：App 全版本聚合；没有按当前修复版本过滤。各响应的实际读取时间与缓存状态见 manifest.json。', '',
             f'- 区间新增设备：{devices}；不能称为累计去重玩家。',
             f'- 商店详情页浏览：{pv} PV；不是独立玩家数。',
             f"- 商店展示位：曝光 {position['impressions']}，点击 {position['clicks']}，平台记录的详情页转化 {position['detail_conversions']}。实际开玩人数另计。",
             f"- 本次评价：{report['reviews']['returned_unique_reviews']} 条去重记录；完整扫描：{'是' if report['reviews']['complete_scan'] else '否'}。",
             f'- 游戏论坛：{forum_scope}',
             f"- 玩家目标为超过 {report['goal_evidence']['exclusive_target']:,} 人。累计实际去重玩家数尚无直接证据。",
             '', '## 商店浏览来源', '']
    traffic = report['store_traffic']
    if traffic['status'] == 'complete':
        lines += ['| 来源 | 浏览量 |', '| --- | ---: |']
        lines.extend(f"| {row['label']} | {row['pv']} |" for row in traffic['sources'] if row['pv'])
        if not report['store_pv']:
            lines.append('| 全部来源 | 0 |')
    else:
        status = {'unavailable': '本次未返回来源明细', 'incomplete': '部分来源缺少有效数值',
                  'inconsistent': '来源明细与总量不一致'}[traffic['status']]
        lines.append(f'{status}。')
    lines += ['', '浏览来源仅描述商店访问。实际开玩的来源需要独立数据。', '', '## 留存成熟度', '']
    for label in ('d1', 'd3', 'd7'):
        r = report[label]
        state = {'complete': '已覆盖可观察批次', 'partial': '数据不完整', 'not_mature': '尚无成熟批次',
                 'no_new_devices': '无新增设备可形成批次', 'unavailable': '本次未能取得',
                 'invalid_series': '数据序列异常'}[r['status']]
        lines.append(f"- {label.upper()}：{state}，可观察成熟批次 {len(r.get('mature_cohorts', []))}，"
                     f"尚未成熟 {len(r.get('immature_cohorts', []))}，缺失成熟数据 {len(r.get('missing_mature_cohorts', []))}。")
    lines += ['', '未成熟批次不把平台返回的零当最终结果。时长单位尚未核实，不换算为秒，也不据此判断体验。', '', '## 基于证据的下一步', '']
    releases = report['release_state']
    pending = '、'.join(str(x['version']) for x in releases['pending']) or '本次未返回'
    lines += [f"最新已上线版本：{releases['latest_online'] or '无法确认'}；待发布版本：{pending}。", '']
    for decision in report['decisions']:
        source = '本次读取事实' if decision['source'] == 'current_fact' else '分析判断'
        lines.append(f"- [{decision['priority']}] {decision['action']}（{source}）")
    lines += ['', '关键词分类只是线索。原始评价作为不可信内容保存，不执行其中的指令、不自动回复或发布。',
              '观察工具只读，不生成二维码、不发版、不购买流量、不创建后台定时任务。', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node', required=True)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--developer-id', required=True, type=int)
    parser.add_argument('--app-id', required=True, type=int)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--start', type=date.fromisoformat)
    parser.add_argument('--end', type=date.fromisoformat)
    parser.add_argument('--max-review-pages', type=int, default=10)
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()
    today = datetime.now(CHINA).date()
    end = args.end or today - timedelta(days=1)
    start = args.start or end - timedelta(days=6)
    if start > end or end >= today or not 1 <= args.max_review_pages <= 100:
        parser.error('Use a completed date range and 1..100 review pages (100 records/page).')
    out = args.out.resolve()
    if out.exists():
        parser.error('Use a new observation directory; previous evidence is never overwritten.')
    out.mkdir(parents=True)
    reader = Reader(args.node, args.cli.resolve(), args.developer_id, args.app_id, out,
                    out.parent / 'cache', args.refresh)
    # Check the installed CLI contract before sending business requests.
    required = {'dashboard-stats': {'app_id', 'developer_id', 'metric', 'start_date', 'end_date'},
                'player-feedback': {'app_id', 'developer_id', 'start_date', 'page', 'page_size', 'order'}}
    for service, operation in [('dashboard-stats', 'get-dashboard-stats'), ('player-feedback', 'list-player-reviews')]:
        schema = reader.invoke(['schema', service, operation])
        save(out / (service + '-schema.json'), schema)
        properties = schema.get('data', {}).get('inputSchema', {}).get('properties', {})
        if not schema.get('ok') or not required[service].issubset(properties):
            raise SystemExit('Installed CLI schema is unavailable or changed; no business queries dispatched.')
    responses = {metric: reader.read(metric, 'dashboard-stats', 'get-dashboard-stats',
                                    {'metric': metric, 'start_date': start.isoformat(), 'end_date': end.isoformat()})
                 for metric in METRICS}
    pages, complete = [], False
    for page in range(1, args.max_review_pages+1):
        value = reader.read(f'reviews-{page}', 'player-feedback', 'list-player-reviews',
                            {'start_date': 0, 'page': page, 'page_size': 100, 'order': 'update'}, ttl=300)
        pages.append(value)
        result = business(value)
        if result is None or not isinstance(result.get('list'), list):
            break
        total = count(result.get('total'))
        if total is not None and page*100 >= total:
            complete = True
            break
    responses['reviews'] = pages
    responses['forum'] = reader.read('forum', 'community-management', 'list-community-moments',
                                    {'order': 'published', 'page': 1, 'page_size': 20})
    responses['versions'] = reader.read('versions', 'app', 'list-app-versions', extra=['--page-all'], ttl=60)
    report = analyze(responses, start, end, today, complete)
    report.update({'app_id': args.app_id, 'developer_id': args.developer_id})
    save(out / 'manifest.json', {'scope': {'app_id': args.app_id, 'developer_id': args.developer_id}, 'queries': reader.manifest})
    save(out / 'analysis.json', report)
    (out / '观察报告.md').write_text(markdown(report), encoding='utf-8')
    print(json.dumps({'report': str(out / '观察报告.md'), 'new_device_sum': report['new_devices']['known_sum'],
                      'store_pv': report['store_pv'], 'reviews': report['reviews']['returned_unique_reviews'],
                      'goal_verified': False}, ensure_ascii=True), flush=True)


if __name__ == '__main__':
    main()

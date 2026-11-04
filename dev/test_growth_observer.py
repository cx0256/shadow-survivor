"""Metric semantics and read-only recovery checks; no real CLI/network calls."""
from datetime import date, datetime, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from growth_observer import Reader, analyze, count, daily_counts, retention, review_evidence, version_evidence


START, END, TODAY = date(2026, 10, 27), date(2026, 11, 2), date(2026, 11, 3)


def envelope(result):
    return {'ok': True, 'data': {'result': result}}


def device_rows():
    return envelope({'series': [{'timestamp': f'2026-10-{27+i}', 'values': {'new_active_device_num': n}}
                               for i, n in enumerate([14, 1, 0, 0, 0])] +
                    [{'timestamp': '2026-11-01', 'values': {'new_active_device_num': 0}},
                     {'timestamp': '2026-11-02', 'values': {'new_active_device_num': 13}}],
                     'summary': {'values': {'new_active_device_num': 4}}})


def ret_rows(value=0):
    return envelope({'series': [{'timestamp': day, 'values': {f'ret_new_active_device_rate_a{lag}d': value for lag in (1,3,7)}}
                               for day in ['2026-10-27', '2026-10-28', '2026-11-02']]})


class MetricSemantics(unittest.TestCase):
    def test_mean_is_not_cumulative_players(self):
        r = analyze({'mini_device': device_rows(), 'mini_ret': ret_rows(), 'reviews': []}, START, END, TODAY)
        self.assertEqual(r['new_devices']['known_sum'], 28)
        self.assertNotEqual(r['new_devices']['known_sum'], 4)
        self.assertIsNone(r['goal_evidence']['cumulative_unique_actual_players'])
        self.assertEqual(r['goal_evidence']['exclusive_target'], 100_000)
        self.assertFalse(r['goal_evidence']['target_verified'])

    def test_device_count_over_target_does_not_prove_players(self):
        d = device_rows()
        d['data']['result']['series'][0]['values']['new_active_device_num'] = 110_000
        r = analyze({'mini_device': d, 'reviews': []}, START, END, TODAY)
        self.assertGreater(r['new_devices']['known_sum'], 100_000)
        self.assertFalse(r['goal_evidence']['target_verified'])

    def test_empty_unknown_and_explicit_zero_remain_different(self):
        empty = daily_counts(envelope({'series': []}), 'new_active_device_num', START, END)
        self.assertIsNone(empty['known_sum'])
        zeros = device_rows()
        for row in zeros['data']['result']['series']:
            row['values']['new_active_device_num'] = 0
        zero = daily_counts(zeros, 'new_active_device_num', START, END)
        self.assertEqual(zero['known_sum'], 0)
        self.assertEqual(zero['status'], 'complete')

    def test_success_envelope_with_upstream_error_is_unknown(self):
        r = daily_counts(envelope({'in_error': True, 'series': []}), 'new_active_device_num', START, END)
        self.assertEqual(r['status'], 'unavailable')
        self.assertIsNone(r['known_sum'])

    def test_missing_date_does_not_fill_zero(self):
        d = device_rows()
        del d['data']['result']['series'][2]
        r = daily_counts(d, 'new_active_device_num', START, END)
        self.assertEqual(r['status'], 'partial')
        self.assertEqual(r['missing_dates'], ['2026-10-29'])
        self.assertNotIn('2026-10-29', r['days'])

    def test_duplicate_or_out_of_scope_dates_rejected(self):
        d = device_rows()
        d['data']['result']['series'].append(d['data']['result']['series'][0])
        self.assertEqual(daily_counts(d, 'new_active_device_num', START, END)['status'], 'invalid_series')
        d = device_rows()
        d['data']['result']['series'][0]['timestamp'] = '2026-10-26'
        self.assertIsNone(daily_counts(d, 'new_active_device_num', START, END)['known_sum'])

    def test_counts_reject_nan_inf_booleans_fractional_and_negative(self):
        for value in (True, False, -1, .5, float('nan'), float('inf'), None, '28'):
            self.assertIsNone(count(value))

    def test_yesterday_cohort_is_not_mature_today(self):
        devices = daily_counts(device_rows(), 'new_active_device_num', START, END)
        d1 = retention(ret_rows(), devices, 1, TODAY, END)
        self.assertEqual([x['date'] for x in d1['mature_cohorts']], ['2026-10-27', '2026-10-28'])
        self.assertEqual(d1['mature_new_devices'], 15)
        self.assertEqual(d1['immature_cohorts'], [{'date': '2026-11-02', 'new_devices': 13}])
        self.assertTrue(d1['all_mature_zero'])
        self.assertIsNone(retention(ret_rows(), devices, 7, TODAY, END)['all_mature_zero'])
        self.assertEqual(retention(ret_rows(), devices, 7, TODAY, END)['status'], 'not_mature')

    def test_missing_mature_rate_cannot_be_called_zero(self):
        devices = daily_counts(device_rows(), 'new_active_device_num', START, END)
        d = ret_rows()
        d['data']['result']['series'][0]['values'] = {}
        r = retention(d, devices, 1, TODAY, END)
        self.assertIsNone(r['all_mature_zero'])
        self.assertEqual(r['status'], 'partial')

    def test_positive_ui_feedback_is_not_relabelled_negative(self):
        row = {'review_id': 7, 'score': 5, 'contents': '建议优化手机界面', 'url': 'https://example.invalid/review/7'}
        r = review_evidence([envelope({'list': [row]}), envelope({'list': [row]})], True)
        self.assertEqual(r['returned_unique_reviews'], 1)
        self.assertEqual(r['topics']['mobile_interface'][0]['score'], 5)
        self.assertFalse(r['topics']['stability'])

    def test_partial_reviews_stay_partial(self):
        r = review_evidence([{'ok': False}], True)
        self.assertFalse(r['complete_scan'])
        self.assertEqual(r['invalid_records_or_pages'], 1)

    def test_duration_and_conversion_do_not_invent_funnel_units(self):
        r = analyze({'mini_device': device_rows(), 'mini_duration': envelope({'highlights': [{'value': '6'}]}),
                     'pv': envelope({'summary': {'values': {'pv_from_total': 616}}}), 'reviews': []}, START, END, TODAY)
        self.assertEqual(r['store_pv'], 616)
        self.assertIn('unverified', r['duration']['unit'])
        self.assertNotIn('pv_to_player_conversion', r)

    def test_store_sources_require_a_complete_breakdown(self):
        values = {'pv_from_total': 616, 'tapmaker_zone': 325, 'game_calendar': 221, 'other': 70}
        pv = envelope({'columns': [{'key': key} for key in values], 'summary': {'values': values}})
        responses = {'pv': pv}
        traffic = analyze(responses, START, END, TODAY)['store_traffic']
        self.assertEqual(traffic['status'], 'complete')
        self.assertEqual([source['pv'] for source in traffic['sources']], [325, 221, 70])
        values['other'] = 69
        self.assertEqual(analyze(responses, START, END, TODAY)['store_traffic']['status'], 'inconsistent')
        del values['other']
        self.assertEqual(analyze(responses, START, END, TODAY)['store_traffic']['status'], 'incomplete')

    def test_position_preserves_missing_and_zero_separately(self):
        position = envelope({'summary': {'values': {'impression_cnt': 8363, 'click_cnt': 0}}})
        report = analyze({'position': position}, START, END, TODAY)
        self.assertEqual(report['store_position'], {'impressions': 8363, 'clicks': 0, 'detail_conversions': None})
        self.assertIsNone(report['goal_evidence']['cumulative_unique_actual_players'])

    def test_forum_scope_distinguishes_posts_from_reviews_and_denied_reads(self):
        forum = envelope({'total': 1, 'list': [{'title': '试玩邀请', 'stat': {'comments': 0}}]})
        report = analyze({'forum': forum}, START, END, TODAY)
        self.assertEqual(report['reviews']['returned_unique_reviews'], 0)
        self.assertEqual(report['forum']['total_visible_posts'], 1)
        self.assertEqual(report['forum']['latest_posts'][0]['comments'], 0)
        self.assertIsNone(analyze({'forum': {'ok': False}}, START, END, TODAY)['forum']['latest_posts'])

    def test_pending_version_is_not_reported_as_online(self):
        rows = [{'version': 'V-20261103', 'status': 'draft', 'created_time': 300},
                {'version': 'V-20261102', 'status': 'online', 'created_time': 200},
                {'version': 'V-20261027', 'status': 'online', 'created_time': 100}]
        versions = version_evidence(envelope({'list': rows, 'total': 3}))
        self.assertEqual(versions['latest_online'], 'V-20261102')
        self.assertEqual(versions['pending'], [{'version': 'V-20261103', 'status': 'draft'}])

    def test_incomplete_version_history_cannot_identify_latest(self):
        versions = version_evidence(envelope({'list': [{'version': 'A', 'status': 'online', 'created_time': 1}], 'total': 2}))
        self.assertEqual(versions['status'], 'partial')
        self.assertIsNone(versions['latest_online'])


class ReadOnlyRecovery(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.temp_root = (root/'.tmp/growth-observer-tests').resolve()
        assert cls.temp_root.is_relative_to(root)
        cls.temp_root.mkdir(parents=True, exist_ok=True)

    def reader(self, directory):
        return Reader('node', Path('official-cli.js'), 502787, 1003383,
                      directory/'observation', directory/'cache')

    def test_retry_transient_once_and_never_add_write_flags(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as temp:
            r = self.reader(Path(temp))
            error = {'ok': False, 'error': {'code': 429, 'retryable': True}}
            good = device_rows()
            with patch.object(r, 'invoke', side_effect=[error, good]) as invoke, patch('growth_observer.time.sleep'):
                self.assertTrue(r.read('devices', 'dashboard-stats', 'get-dashboard-stats', {'metric': 'mini_device'})['ok'])
            self.assertEqual(invoke.call_count, 2)
            args = invoke.call_args.args[0]
            self.assertNotIn('--yes', args)
            self.assertNotIn('--idempotency-key', args)
            self.assertEqual(r.manifest[0]['attempts'], 2)

    def test_permission_error_does_not_reauthenticate_or_rotate_scope(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as temp:
            r = self.reader(Path(temp))
            with patch.object(r, 'invoke', return_value={'ok': False, 'error': {'code': 403}}) as invoke:
                r.read('devices', 'dashboard-stats', 'get-dashboard-stats')
            self.assertEqual(invoke.call_count, 1)
            self.assertFalse(r.manifest[0]['ok'])

    def test_cache_preserves_freshness_and_scope(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as temp:
            directory = Path(temp)
            first = self.reader(directory)
            with patch.object(first, 'invoke', return_value=device_rows()) as invoke:
                first.read('devices', 'dashboard-stats', 'get-dashboard-stats', {'metric': 'mini_device'})
                first.read('devices-cached', 'dashboard-stats', 'get-dashboard-stats', {'metric': 'mini_device'})
            self.assertEqual(invoke.call_count, 1)
            self.assertTrue(first.manifest[-1]['cached'])
            self.assertEqual(first.manifest[0]['fetched_at'], first.manifest[-1]['fetched_at'])
            second = Reader('node', Path('official-cli.js'), 502787, 999999,
                            directory/'different-app', directory/'cache')
            with patch.object(second, 'invoke', return_value=device_rows()) as invoke:
                second.read('devices', 'dashboard-stats', 'get-dashboard-stats', {'metric': 'mini_device'})
            self.assertEqual(invoke.call_count, 1)

    def test_invalid_cli_output_stays_unknown(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as temp:
            r = self.reader(Path(temp))
            with patch('growth_observer.subprocess.run') as run:
                run.return_value.stdout = b'not JSON'
                run.return_value.stderr = b''
                run.return_value.returncode = 0
                value = r.invoke(['dashboard-stats', 'get-dashboard-stats'])
            self.assertFalse(value['ok'])


if __name__ == '__main__':
    unittest.main()

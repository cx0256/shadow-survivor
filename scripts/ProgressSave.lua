local ProgressSave={}

local function read(path)
    if not fileSystem:FileExists(path) then return nil end
    local file=File(path,FILE_READ)
    if not file or not file:IsOpen() then return nil end
    local text=file:ReadString()
    file:Close()
    return text
end

local function decode(text)
    if not text then return nil end
    local ok,value=pcall(cjson.decode,text)
    if ok and type(value)=="table" then return value end
end

function ProgressSave.Load(path)
    local newest,generation=nil,0
    for slot=0,1 do
        local value=decode(read(path.."."..slot))
        if value and type(value.generation)=="number" and value.generation>generation
            and value.generation<math.huge and value.generation%1==0 and value.generation%2==slot
            and type(value.progress)=="table" and type(value.progress.runs)=="number" then
            newest,generation=value.progress,value.generation
        end
    end
    return newest or decode(read(path)) or {},generation
end

function ProgressSave.Write(path,progress,generation)
    local nextGeneration=generation+1
    -- Write the other slot, leaving the newest known-good save untouched.
    local destination=path.."."..(nextGeneration%2)
    local text=cjson.encode({generation=nextGeneration,progress=progress})
    local file=File(destination,FILE_WRITE)
    if not file or not file:IsOpen() then return nil,"open_failed" end
    local written=file:WriteString(text)
    file:Close()
    if not written then return nil,"write_failed" end
    if read(destination)~=text then return nil,"verify_failed" end
    return nextGeneration
end

return ProgressSave

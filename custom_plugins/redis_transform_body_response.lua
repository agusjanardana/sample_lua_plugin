-- local common libs
local require   = require
local redis_new = require("resty.redis").new
local log_util = require("apisix.utils.log-util")
local core        = require("apisix.core")
local ngx       = ngx
-- local function

-- module define
local plugin_name = "redis_transform_body_response"

local plugin_schema = {}

local _M = {
    version  = 0.1,            -- plugin version
    priority = 1000,              -- the priority of this plugin will be 1
    name     = plugin_name,    -- plugin name
    schema   = plugin_schema,  -- plugin schema
}

local function extract_session_id(xml_string)
    local pattern = "<GetSessionIdResponse[^>]*>(.-)</GetSessionIdResponse>"

    -- Lakukan pencocokan dengan ekspresi regular
    local session_id = string.match(xml_string, pattern)

    -- Cetak hasil
    if session_id then
        ngx.log(ngx.INFO, "Session ID: ", session_id)
        return session_id
    else
        ngx.log(ngx.ERR, "Failed to extract Session ID from XML response")
        return nil
    end
end

function _M.body_filter(conf, ctx)
    core.log.warn("Fase Content filter")
    local body = core.response.hold_body_chunk(ctx)
    if not body then
        return core.log.warn("failed to hold response body chunk")
    end

    ngx.arg[1] = body
    ngx.arg[2] = true
   
    -- Extract and store session ID in shared memory dictionary
    local sessionid = extract_session_id(ngx.arg[1])
   
    if ngx.arg[2] then
        core.log.warn("body filter, chunk: ", sessionid)
    end

    -- core.log.warn(sessionid)

    -- if sessionid then
    --     ngx.arg[1] = sessionid
    -- end
end

return _M
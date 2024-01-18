
-- local common libs
local require   = require
local redis_new = require("resty.redis").new
local log_util  = require("apisix.utils.log-util")
local core      = require("apisix.core")
local http      = require "resty.http"
local ngx       = ngx

-- local function

-- module define
local plugin_name = "redis_session_log"

-- plugin schema
local plugin_schema = {
}

local _M = {
    version  = 0.1,            -- plugin version
    priority = 1500,           -- the priority of this plugin will be 0
    name     = plugin_name,    -- plugin name
    schema   = plugin_schema,  -- plugin schema
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(plugin_schema, conf)
end


local function extract_session_id(xml_string)
    local pattern = "<GetSessionIdResponse[^>]*>(.-)</GetSessionIdResponse>"

    -- Lakukan pencocokan dengan ekspresi regular
    local data = string.match(xml_string, pattern)

    local patternSessionId = "<sessionId>(.-)</sessionId>"
    local patternClientId = "<clientId>(.-)</clientId>"

    -- Cetak hasil
    if data then
        local returnData = {
            session_id = string.match(data, patternSessionId),
            client_id = string.match(data, patternClientId)
        }

        core.log.warn(returnData.client_id)
        return returnData
    else
        ngx.log(ngx.ERR, "Failed to extract Session ID from XML response")
        return nil
    end
end




-- function _M.access(conf, ctx)
--     core.log.warn("Fase Access")


-- end

local bodySession
local clientId
local location

function _M.body_filter(conf, ctx)
    local body = core.response.hold_body_chunk(ctx)
    if not body then
        return ngx.log(ngx.NOTICE, "processing body")
    end


    ngx.arg[1] = body
    ngx.arg[2] = true
   
    -- Extract and store session ID in shared memory dictionary
    local data = extract_session_id(ngx.arg[1])
    if data then 
        bodySession = data.session_id
        clientId = data.client_id
    else 
        core.log.warn("Failed to extract Session ID from XML response")
    end


    -- extract header
    local h, err = ngx.resp.get_headers()
    if err == "truncated" then
        -- one can choose to ignore or reject the current response here
        core.log.warn("truncated response headers from ", ngx.var.upstream_addr)
    end

    for k, v in pairs(h) do
        if k == "location" then
            location = v
        end
    end
    if not location then
        core.log.warn("failed to get Location header")
        return
    end

    core.log.warn("Location: ", location)
end

function _M.log(conf, ctx)
    local function redis_client()
        local red = redis_new()
        local timeout =  1000    -- 1sec

        red:set_timeouts(timeout, timeout, timeout)

        local sock_opts = {
            ssl = conf.ssl,
            ssl_verify = conf.ssl_verify
        }

        local ok, err = red:connect("host.docker.internal", 6379, sock_opts)
        if not ok then
            return false, err
        end
        return red, nil
    end                
    
    local function save_redis()
        local redis_cli = redis_client()
        redis_cli:set(clientId,  bodySession)
        redis_cli:expire(clientId, 50)
    end
    
    ngx.timer.at(0, save_redis)
end

return _M


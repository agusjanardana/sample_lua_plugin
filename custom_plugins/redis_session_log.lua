
-- local common libs
local require   = require
local redis_new = require("resty.redis").new
local log_util  = require("apisix.utils.log-util")
local core      = require("apisix.core")
local http      = require "resty.http"
local ngx       = ngx
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")

-- local function

-- module define
local plugin_name = "redis_session_log"
local batch_processor_manager = bp_manager_mod.new("http logger")


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




-- function _M.access(conf, ctx)
--     core.log.warn("Fase Access")


-- end

local bodySession

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
    bodySession = sessionid
    core.log.warn(bodySession)
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
        redis_cli:set("NEW-1234567",  bodySession)
    end
    
    ngx.timer.at(0, save_redis)
end

return _M


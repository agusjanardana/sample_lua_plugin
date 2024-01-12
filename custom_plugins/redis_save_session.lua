
-- local common libs
local require   = require
local redis_new = require("resty.redis").new
local log_util = require("apisix.utils.log-util")
local core        = require("apisix.core")
local ngx       = ngx
-- local function

-- module define
local plugin_name = "redis_save_session"

-- plugin schema
local plugin_schema = {
    type = "object",
    properties = {
        redis = {
            properties = {
                host = {
                    type = "string", minLength = 2
                },
                port = {
                    type = "integer", minimum = 1, default = 6379,
                },
                username = {
                    type = "string", minLength = 1,
                },
                password = {
                    type = "string", minLength = 0,
                },
                database = {
                    type = "integer", minimum = 0, default = 0,
                },
                timeout = {
                    type = "integer", minimum = 1, default = 1000,
                },
                ssl = {
                    type = "boolean", default = false,
                },
                ssl_verify = {
                    type = "boolean", default = false,
                },
            },
            required = {"host"},
        },
        include_resp_body = {type = "boolean", default = true},
    },
}

local _M = {
    version  = 0.1,            -- plugin version
    priority = 1000,              -- the priority of this plugin will be 0
    name     = plugin_name,    -- plugin name
    schema   = plugin_schema,  -- plugin schema
}

local function redis_client(conf)
    local red = redis_new()
    local timeout = conf.timeout or 1000    -- 1sec

    red:set_timeouts(timeout, timeout, timeout)

    local sock_opts = {
        ssl = conf.ssl,
        ssl_verify = conf.ssl_verify
    }

    local ok, err = red:connect(conf.host, conf.port or 6379, sock_opts)
    if not ok then
        return false, err
    end

    local count
    count, err = red:get_reused_times()
    if 0 == count then
        if conf.password and conf.password ~= '' then
            local ok, err
            if conf.username then
                ok, err = red:auth(conf.username, conf.password)
            else
                ok, err = red:auth(conf.password)
            end
            if not ok then
                return nil, err
            end
        end

        -- select db
        if conf.database ~= 0 then
            local ok, err = red:select(conf.database)
            if not ok then
                return false, "failed to change redis db, err: " .. err
            end
        end
    elseif err then
        return nil, err
    end
    return red, nil
end

local function json_response(status, body)
    ngx.header['Content-Type'] = "application/json"
    return status, body
end

function _M.check_schema(conf, schema_type)
    return core.schema.check(plugin_schema, conf)
end


function _M.access(conf, ctx)   
    
    core.log.warn("Fase Access")
    -- 2. Save session ID to Redis
    local redis_cli = redis_client(conf.redis)
    if not redis_cli then
        return json_response(500, { message = "Session storage is unavailable" })
    end
    
    -- core.log.warn(ctx.sessionid)
    local sessionid = ngx.arg[1]
    redis_cli:set("NEW-123", sessionid)
    

    return ctx.sessionid
end



-- local function async_redis_set(session_id, conf)
--     local redis_cli = redis_new()

--     local ok, err = redis_cli:connect(conf.host, conf.port or 6379)
--     if not ok then
--         ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
--         return
--     end

--     local _, err = ngx.thread.spawn(function()
--         local _, err = redis_cli:set(session_id, session_id)
--         if not _ then
--             ngx.log(ngx.ERR, "Failed to set data in Redis: ", err)
--         end
--     end)

--     if err then
--         ngx.log(ngx.ERR, "Failed to spawn thread: ", err)
--     end

--     local _, err = ngx.thread.wait()
--     if err then
--         ngx.log(ngx.ERR, "Failed to wait for thread: ", err)
--     end

--     local ok, err = redis_cli:close()
--     if not ok then
--         ngx.log(ngx.ERR, "Failed to close Redis connection: ", err)
--     end
-- end



-- function _M.body_filter(conf, ctx)
--     local body = core.response.hold_body_chunk(ctx)
--     if not body then
--         return
--     end
--     ngx.arg[1] = body
--     ngx.arg[2] = true
-- end



-- function _M.body_filter(conf, ctx)
--     local body = core.response.hold_body_chunk(ctx)
--     if not body then
--         return
--     end
--     ngx.arg[1] = body
--     ngx.arg[2] = true
--     core.log.warn(conf.redis.host)
--     core.log.warn(conf.redis.port)
--     core.log.warn(ngx.arg[1])

--     -- 1. Extract session ID from the response body

--     local session_id
--     if ngx.arg[2] then
--          session_id = extract_session_id(ngx.arg[1])
--         core.log.warn(session_id)
--     end
  
--     -- 2. Save session ID to Redis
--     local redis_cli = async_redis_set(session_id, conf.redis)
--     if not redis_cli then
--         return json_response(500, { message = "Session storage is unavailable" })
--     end

--     if not session_id then
--         return json_response(401, { message = "Invalid session" })
--     end
-- end

return _M

-- function _M.body_filter(conf, ctx)
--     -- 1. collect body dulu, dari utils lalu jump ke hold_body_chunk
--     log_util.collect_body(conf, ctx)

--     -- 2. syarat bsia collect body adalah include_resp_body = true yang di tempel di parameter, sudah buat default true
--     -- 3. collect body akan memberikan body yang di simpan di ctx
--     local local_body = ctx.resp_body

--     -- 4. extract session id dari body
--     local session_id = extract_session_id(local_body)

--     -- 5. simpan session id ke redis
--     local redis_cli = redis_client(conf.redis)
--     if not redis_cli then
--         return json_response(500, { message = "Session storage is unavailable" })
--     end

--     local exist = redis_cli:exists(session_id)

--     if session_id then
--         redis_cli:set(session_id, session_id)
--     end

--     if not session_id then
--         return json_response(401, { message = "Invalid session" })
--     end
    
-- end


-- return _M

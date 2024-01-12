--- Steps
-- 1. User send LGI request to your service, configure a route without plugin
-- 2. Server side verify user identity, if login is success, save user session id to Redis with JSON session data,
--    you can store some fields in it to help identify user when user send CMD request
-- 3. User send CMD request, you need to create a route and enable this plugin for it.
--    When the request comes in, the plugin will fetch the session_data corresponding to the session_key from redis and
--    write the data you want into the request header to the upstream (the request header is nice, if your service can support it).
-- 4. Your upstream service handles user's CMD request with user indentity.
-- 5. User send LGO request to logout, you can remove the session data from redis.

--- TIPS
-- 1. Redis is good for sharing data when you use multiple APISIX instances (e.g. for load balancing and disaster recovery), which is not possible with shared memory.
-- 2. Redis is replaceable, and you can replace it with RDBMS software such as PostgreSQL.
-- 3. The session's 50s maintenance time, which you can achieve with the redis ttl feature.
-- 4. It is not secure to use only URI as session ID. This means that if I get your session ID by guessing etc., it means I can request business system to act you identity.

--- Configuration demo
--
-- { "session_key": "$uri", "redis": { "host": "127.0.0.1" } }
--
-- Which mean, the plugin will get session from Nginx variable "$uri", it will like "/0050000".
-- And then, use this value as the session_key to fetch session_data from Redis


-- local common libs
local require   = require
local redis_new = require("resty.redis").new
local core      = require("apisix.core")
local ngx       = ngx

-- local function

-- module define
local plugin_name = "redis_get_session"

-- plugin schema
local plugin_schema = {
    type = "object",
    properties = {
        session_key = {
            type = "string",
            minLength = 1,
            description = "The gateway tries to get the session key from somewhere, and can use APISIX and Nginx variables."
        },
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
        }
    },
    required = {"session_key", "redis"},
}

local _M = {
    version  = 0.1,            -- plugin version
    priority = 300,              -- the priority of this plugin will be 0
    name     = plugin_name,    -- plugin name
    schema   = plugin_schema,  -- plugin schema
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(plugin_schema, conf)
end


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


function _M.access(conf, ctx)
    local session_key = core.utils.resolve_var(conf.session_key, ctx.var)
    if not session_key then
        return json_response(401, { message = "No session key found" })
    end

    local redis_cli = redis_client(conf.redis)
    if not redis_cli then
        return json_response(500, { message = "Session storage is unavailable" })
    end

    local exist = redis_cli:exists(session_key)
    if exist == 0 then
        ngx.log(ngx.ERR, "Invalid session, session not exist, session key: ", session_key)
        return json_response(401, { message = "Invalid session" })
    end

    local session_data, err = redis_cli:get(session_key)
    if not session_data or session_data == ngx.null then
        return json_response(401, { message = "Invalid session" })
    end

    session_data, err = core.json.decode(session_data)
    if not session_data or type(session_data) ~= "table" then
        core.log.error("Error in JSON parsing of session data, type: ", type(session_data), ", err: ", err)
        return json_response(500, { message = "Invalid session data" })
    end

    -- e.g. pass user identity to upstream service
    core.request.set_header(ctx, "X-Subscriber-ID", session_data["MSISDN"])
end


return _M

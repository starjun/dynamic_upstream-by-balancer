-----  rewrite_all by zj  -----
local ngx_var  = ngx.var
local ngx_ctx  = ngx.ctx
local modcache = require("modcache")
local optl   = require("optl")
local string_upper = string.upper
local unescape_uri = ngx.unescape_uri
local ngx_redirect = ngx.redirect
local ngx_shared = ngx.shared

local config = modcache.keys["config"].cache

local limit_ip_dict = ngx_shared.limit_ip_dict
local ip_dict       = ngx_shared.ip_dict

local host = unescape_uri(ngx_var.http_host)
local scheme = ngx_var.scheme
local request_uri = unescape_uri(ngx_var.request_uri)
local uri = ngx_var.uri
local ip  = ngx_var.remote_addr

local function remath_ext(_str , _modRule)
    if type(_modRule) ~= "table" then
        return false
    end
    if _modRule[2] == "rein_list" or _modRule[2] == "restart_list" or _modRule[2] == "reend_list" then
        return optl.remath_Invert(string_upper(_str) , _modRule[1] , _modRule[2] , _modRule[3])
    else
        return optl.remath_Invert(_str , _modRule[1] , _modRule[2] , _modRule[3])
    end
end

--- 匹配 host 和 uri
local function host_uri_remath(_host , _uri)
    if remath_ext(host , _host) and remath_ext(uri , _uri) then
        return true
    end
end

--- 取config_dict中的json数据
local function getDict_Config(_Config_jsonName)
    local re = config[_Config_jsonName] or {}
    return re
end

--- 访问频率检查 并且计数
-- _tb_network 频率规则  _uid 唯一标识
-- true:触发 频率限制  false:未触发 计数++
local function network_ck(_tb_network , _uid)
    if type(_tb_network) ~= "table" then
        return
    end
    local pTime    = _tb_network.pTime or 10
    local maxReqs  = _tb_network.maxReqs or 50
    local ip_count = limit_ip_dict:get(_uid)
    if ip_count == nil then
        limit_ip_dict:set(_uid , 1 , pTime)
        return
    else
        if ip_count >= maxReqs then
            limit_ip_dict:delete(_uid)
            return true
        else
            limit_ip_dict:incr(_uid , 1)
            return
        end
    end
end

-- ip_Mod 执行
do
    local _ip_v = ip_dict:get(ip) --- 全局IP 黑白名单
    if _ip_v ~= nil then
        if _ip_v == "allow" then
            -- 跳出后续规则
            return
        else
            ngx.exit(403)
        end
    end
    -- 基于host的ip黑白名单 eg:www.abc.com_101.111.112.113
    local ip_tmp  = host .. "_" .. ip
    local host_ip = ip_dict:get(ip_tmp)
    if host_ip ~= nil then
        if host_ip == "allow" then
            -- 跳出后续规则
            return
        else
            ngx.exit(403)
        end
    end
end

-- http2https_Mod 执行
if scheme == "http" then
    for i,v in ipairs(getDict_Config("http2https_Mod")) do
        if v.state == "on" and remath_ext(host,v.hostname) then
            return ngx_redirect("https://"..host..request_uri,301)
        end
    end
end

-- proxy_cache_Mod 执行
for i,v in ipairs(getDict_Config("proxy_cache_Mod")) do
    if v.state == "on" and host_uri_remath(v.hostname , v.uri) then
        ngx_var.p_cache = 0
    end
end

-- limit_rate_Mod 执行
for i,v in ipairs(getDict_Config("limit_rate_Mod")) do
    if v.state == "on" and host_uri_remath(v.hostname , v.uri) then
        ngx_var.limit_rate = v.limit_rate or "100k"
    end
end

-- network_Mod 执行
for i,v in ipairs(getDict_Config("network_Mod")) do
    if v.state == "on" and host_uri_remath(v.hostname , v.uri) then
        local mod_ip = ip .. " network_Mod No " .. i
        if network_ck(v.network , mod_ip) then
            local blacktime = v.network.blackTime or 10 * 60
            if v.hostname[2] == "" then
                if v.hostname[1] == "*" then
                    ip_dict:safe_set(ip , mod_ip , blacktime)
                else
                    ip_dict:safe_set(host .. "_" .. ip , mod_ip , blacktime)
                end
            else
                ip_dict:safe_set(host .. "_" .. ip , mod_ip , blacktime)
            end
            ngx.exit(403)
            break
        end
    end
end

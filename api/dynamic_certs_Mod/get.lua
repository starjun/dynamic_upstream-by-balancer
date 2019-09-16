-- 动态证书查询
local stool = require "stool"
local optl  = require "optl"
local _host = optl.get_paramByName("host")
local config_dict = ngx.shared["config_dict"]

local _tb = stool.tableTojsonStr(config_dict:get("dynamic_certs")) or {}
if _host == "" then
    local _tb_host_name = {}
    for k,v in pairs(_tb) do
        table.insert(_tb_host_name,k)
    end
    optl.sayHtml_ext({code="ok",msg=_tb_host_name,count=#(_tb_host_name)})
elseif _host == "all_host" then
    local tmp = {}
    for k,v in pairs(_tb) do
        v.ssl_certificate_key = nil
        tmp[k] = v
    end
    optl.sayHtml_ext({code="ok",msg=tmp})
else
    optl.sayHtml_ext({code="ok",msg=_tb[_host]})
end
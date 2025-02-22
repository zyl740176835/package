module("luci.model.cbi.passwall2.server.api.v2ray", package.seeall)
local uci = require"luci.model.uci".cursor()

function gen_config(user)
    local settings = nil
    local routing = nil
    local outbounds = {
        {protocol = "freedom", tag = "direct"}, {protocol = "blackhole", tag = "blocked"}
    }

    if user.protocol == "vmess" or user.protocol == "vless" then
        if user.uuid then
            local clients = {}
            for i = 1, #user.uuid do
                clients[i] = {
                    id = user.uuid[i],
                    flow = ("vless" == user.protocol and "1" == user.tls and user.tlsflow) and user.tlsflow or nil
                }
            end
            settings = {
                clients = clients,
                decryption = user.decryption or "none"
            }
        end
    elseif user.protocol == "socks" then
        settings = {
            udp = ("1" == user.udp_forward) and true or false,
            auth = ("1" == user.auth) and "password" or "noauth",
            accounts = ("1" == user.auth) and {
                {
                    user = user.username,
                    pass = user.password
                }
            } or nil
        }
    elseif user.protocol == "http" then
        settings = {
            allowTransparent = false,
            accounts = ("1" == user.auth) and {
                {
                    user = user.username,
                    pass = user.password
                }
            } or nil
        }
        user.transport = "tcp"
        user.tcp_guise = "none"
    elseif user.protocol == "shadowsocks" then
        settings = {
            method = user.method,
            password = user.password,
            ivCheck = ("1" == user.iv_check) and true or false,
            network = user.ss_network or "TCP,UDP"
        }
    elseif user.protocol == "trojan" then
        if user.uuid then
            local clients = {}
            for i = 1, #user.uuid do
                clients[i] = {
                    password = user.uuid[i]
                }
            end
            settings = {
                clients = clients
            }
        end
    elseif user.protocol == "mtproto" then
        settings = {
            users = {
                {
                    secret = (user.password == nil) and "" or user.password
                }
            }
        }
    elseif user.protocol == "dokodemo-door" then
        settings = {
            network = user.d_protocol,
            address = user.d_address,
            port = tonumber(user.d_port)
        }
    end

    if user.fallback and user.fallback == "1" then
        local fallbacks = {}
        for i = 1, #user.fallback_list do
            local fallbackStr = user.fallback_list[i]
            if fallbackStr then
                local tmp = {}
                string.gsub(fallbackStr, '[^' .. "," .. ']+', function(w)
                    table.insert(tmp, w)
                end)
                local dest = tmp[1] or ""
                local path = tmp[2]
                if dest:find("%.") then
                else
                    dest = tonumber(dest)
                end
                fallbacks[i] = {
                    path = path,
                    dest = dest,
                    xver = 1
                }
            end
        end
        settings.fallbacks = fallbacks
    end

    routing = {
        domainStrategy = "IPOnDemand",
        rules = {
            {
                type = "field",
                ip = {"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"},
                outboundTag = (user.accept_lan == nil or user.accept_lan == "0") and "blocked" or "direct"
            }
        }
    }

    if user.outbound_node and user.outbound_node ~= "nil" then
        local outbound_node_t = uci:get_all("passwall2", user.outbound_node)
        if user.outbound_node == "_socks" or user.outbound_node == "_http" then
            outbound_node_t = {
                type = user.type,
                protocol = user.outbound_node:gsub("_", ""),
                transport = "tcp",
                address = user.outbound_node_address,
                port = user.outbound_node_port,
                username = (user.outbound_node_username and user.outbound_node_username ~= "") and user.outbound_node_username or nil,
                password = (user.outbound_node_password and user.outbound_node_password ~= "") and user.outbound_node_password or nil,
            }
        end
        local outbound = require("luci.model.cbi.passwall2.api.gen_v2ray").gen_outbound(outbound_node_t, "outbound")
        if outbound then
            table.insert(outbounds, 1, outbound)
        end
    end

    local config = {
        log = {
            -- error = "/tmp/etc/passwall2_server/log/" .. user[".name"] .. ".log",
            loglevel = ("1" == user.log) and user.loglevel or "none"
        },
        -- 传入连接
        inbounds = {
            {
                listen = (user.bind_local == "1") and "127.0.0.1" or nil,
                port = tonumber(user.port),
                protocol = user.protocol,
                settings = settings,
                streamSettings = {
                    network = user.transport,
                    security = "none",
                    tlsSettings = ("1" == user.tls) and {
                        disableSystemRoot = false,
                        certificates = {
                            {
                                certificateFile = user.tls_certificateFile,
                                keyFile = user.tls_keyFile
                            }
                        }
                    } or nil,
                    tcpSettings = (user.transport == "tcp") and {
                        acceptProxyProtocol = (user.acceptProxyProtocol and user.acceptProxyProtocol == "1") and true or false,
                        header = {
                            type = user.tcp_guise,
                            request = (user.tcp_guise == "http") and {
                                path = user.tcp_guise_http_path or {"/"},
                                headers = {
                                    Host = user.tcp_guise_http_host or {}
                                }
                            } or nil
                        }
                    } or nil,
                    kcpSettings = (user.transport == "mkcp") and {
                        mtu = tonumber(user.mkcp_mtu),
                        tti = tonumber(user.mkcp_tti),
                        uplinkCapacity = tonumber(user.mkcp_uplinkCapacity),
                        downlinkCapacity = tonumber(user.mkcp_downlinkCapacity),
                        congestion = (user.mkcp_congestion == "1") and true or false,
                        readBufferSize = tonumber(user.mkcp_readBufferSize),
                        writeBufferSize = tonumber(user.mkcp_writeBufferSize),
                        seed = (user.mkcp_seed and user.mkcp_seed ~= "") and user.mkcp_seed or nil,
                        header = {type = user.mkcp_guise}
                    } or nil,
                    wsSettings = (user.transport == "ws") and {
                        acceptProxyProtocol = (user.acceptProxyProtocol and user.acceptProxyProtocol == "1") and true or false,
                        headers = (user.ws_host) and {Host = user.ws_host} or nil,
                        path = user.ws_path
                    } or nil,
                    httpSettings = (user.transport == "h2") and {
                        path = user.h2_path, host = user.h2_host
                    } or nil,
                    dsSettings = (user.transport == "ds") and {
                        path = user.ds_path
                    } or nil,
                    quicSettings = (user.transport == "quic") and {
                        security = user.quic_security,
                        key = user.quic_key,
                        header = {type = user.quic_guise}
                    } or nil,
                    grpcSettings = (user.transport == "grpc") and {
                        serviceName = user.grpc_serviceName
                    } or nil
                }
            }
        },
        -- 传出连接
        outbounds = outbounds,
        routing = routing
    }

    local alpn = {}
    if user.alpn then
        string.gsub(user.alpn, '[^' .. "," .. ']+', function(w)
            table.insert(alpn, w)
        end)
    end
    if alpn and #alpn > 0 then
        if config.inbounds[1].streamSettings.tlsSettings then
            config.inbounds[1].streamSettings.tlsSettings.alpn = alpn
        end
    end

    if "1" == user.tls then
        config.inbounds[1].streamSettings.security = "tls"
    end

    return config
end

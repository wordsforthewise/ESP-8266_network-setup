--this file must be compiled to run properly, otherwise you will 
--probably run out of memory as I did

local SSID = nil
local pass = nil
local otherSSID = nil
local errMsg = nil
local savedNetwork = false
local SSIDs = {}
--lookup table for wifi.sta.status()
local statusTable = {}
--statusTable[0] = "neither connected nor connecting"
--statusTable[1] = "still connecting"
statusTable["2"] = "wrong password"
statusTable["3"] = "didn\'t find the network you specified"
statusTable["4"] = "failed to connect"
--statusTable[5] = "successfully connected"

collectgarbage()
wifi.setmode(wifi.STATIONAP)
print('wifi status: '..wifi.sta.status())
print(node.heap())

--opens saved list of nearby networks and puts into SSIDs table
file.open('networkList','r')
local counter = 0
local line = ""
while (true) do
    line = file.readline()
    if line == nil then break end
    counter = counter + 1
    SSIDs[counter] = line
end

print(node.heap())

--start server running on ESP-8266, usually is IP 192.168.4.1
local cfg = {}
cfg.ssid = "myfi"
cfg.pwd = "mystical"
wifi.ap.config(cfg)
cfg = nil
local srv=net.createServer(net.TCP,30)
print('connect to this ip on your computer/phone: '..wifi.ap.getip())
srv:listen(80,function(conn)

conn:on("receive", function(client,request)
    local connecting = false
    local _, _, SSID, pass = string.find(request, "SSID=(.+)%%0D%%0A&otherSSID=&password=(.*)");
    print(node.heap())

    if (pass~=nil and pass~="") then
        if (string.len(pass)<8) then
            local pass = nil
            errMsg = "<center><h2 style=\"color:red\">Whoops! Password must be at least 8 characters.<\h2><\center>"
        end
    end
    
    if (SSID==nil) then
        _, _, SSID, pass = string.find(request, "SSID=&otherSSID=(.+)%%0D%%0A&password=(.*)");
    end

    print(request)
    local buf = "";
    print(SSID)
    print(pass)

    --if password for network is nothing, any password should work
    if (SSID~=nil) then
        if (pass == "") then
            pass = "aaaaaaaa"
        end
        print(SSID..', '..pass)
        wifi.sta.config(tostring(SSID),tostring(pass))
        wifi.sta.connect()
        connecting = true
    end
    --had to chunk up sending of webpage, to deal with low amounts of memory on ESP-8266 devices...surely a more elegant way to do it
    buf = buf.."<!DOCTYPE html><html><head><style>h2{font-size:200%; font-family:helvetica} p{font-size:200%; font-family:helvetica}</style></head><div style = \"width:80%; margin: 0 auto\">"
    buf = buf.."<h2>choose a network to join</h2>";
    buf = buf.."<form  align = \"left\" method=\"POST\" autocomplete=\"off\">";
    buf = buf.."<p><u><b>1. choose network:</u></b><br>"
    client:send(buf)
    print('first send')
    buf = ""
    --send network names one at a time; if there are lots of networks the ESP can run out of memory
    for i,network in pairs(SSIDs) do
        buf = "<input type=\"radio\" name=\"SSID\" value=\""..network.."\">"..network.."<br>"
        client:send(buf)
        buf = ""
    end
    buf = buf.."other: <input type=\"text\" name=\"otherSSID\"><br><br>";
    buf = buf.."<u><b>2. enter password:</u></b><br><input type=\"text\" name=\"password\"><br><br>";
    buf = buf.."<input type=\"submit\" value=\"Submit\">";
    buf = buf.."</p></form></div>";
    client:send(buf)
    buf = ""
    --add warning about password<8 characters if needed
    if (errMsg~=nil) then
        buf = buf.."<br><br>"..errMsg
        errMsg = nil
    end
    --if found SSID in the POST from the client, try connecting
    if (SSID~=nil) then
        local connectStatus = wifi.sta.status()
        print(connectStatus)
        
        tmr.alarm(1,1000,1, function()
            connectStatus = wifi.sta.status()
            print("connecting")
            if (connectStatus ~= 1) then
                print("connectStatus = "..tostring(connectStatus))
                buf = buf.."<br><center>"
                if (connectStatus == 5) then
                    buf = buf.."<h2 style=\"color:DarkGreen\">Successfully connected to "..tostring(SSID).."!</h2><br><h2>Added to network list.</h2><br><h2>Resetting module and connecting to the mystical network...</h1>"
                    file.open("networks","a+")
                    file.writeline(tostring(SSID))
                    file.writeline(tostring(pass))
                    file.close()
                    savedNetwork = true
                else
                    buf = buf.."<h2 style=\"color:red\">Whoops! Could not connect to "..tostring(SSID)..". "..statusTable[tostring(connectStatus)].."</h2><br>"
                end
                buf = buf.."</center>"
                client:send(buf)
                client:close()
                collectgarbage()
                tmr.stop(1)
            end
        end)
    end
    --TO-DO: need to add the functionality for this button
    buf = buf.."<br><br><br><form method=\"GET\"><input type=\"submit\" value=\"edit saved network info\"></form></html>"
    if(not connecting) then
        client:send(buf)
        buf = ""
        client:close()
        collectgarbage()
    end
    if(savedNetwork) then
        tmr.alarm(2,6000,0,function()
            srv:close()
            node.restart()
            end
        )
    end
end)
end)

#!/usr/bin/env python

import cgi
import urllib
import json

url = 'http://bustime.mta.info/api/siri/stop-monitoring.json?'
key = '931355e2-2bfd-4ba9-a788-6139e24ab145'

form = cgi.FieldStorage()
stop_id = form.getfirst("StopId", 999999)

def get_data(stop_id, url):
    url += urllib.urlencode({'MonitoringRef':stop_id, 'key': key})
    data = urllib.urlopen(url)
    js_data= json.load(data)
    bus_info = js_data["Siri"]["ServiceDelivery"]["StopMonitoringDelivery"][0]["MonitoredStopVisit"][0]["MonitoredVehicleJourney"]
    return bus_info

def get_distance(json_obj):
    distance = json_obj["MonitoredCall"]["Extensions"]["Distances"]["DistanceFromCall"]
    return distance

def get_latitude(json_obj):
    latitude = json_obj["VehicleLocation"]["Latitude"]
    return latitude

def get_longitude(json_obj):
    longitude = json_obj["VehicleLocation"]["Longitude"]
    return longitude

def get_busname(json_obj):
    busname = json_obj["PublishedLineName"]
    return busname

def process_data(stop_id, json_obj):
    if json_obj:
        bus_info = json_obj
        latitude = str(get_latitude(bus_info))
        longitude = str(get_longitude(bus_info))
        busname = get_busname(bus_info)
        distance = str(round(get_distance(bus_info) * 0.000621371, 2))
        return (latitude, longitude, distance, busname)

latitude  = process_data(stop_id, get_data(stop_id, url))[0]
longitude = process_data(stop_id, get_data(stop_id, url))[1]
distance  = process_data(stop_id, get_data(stop_id, url))[2]
busname   = process_data(stop_id, get_data(stop_id, url))[3]

print "Content-Type: text/html\n\n"

print """
<?xml version="1.0" encoding="UTF-8"?>
<html>
<head>
    <meta content="text/html;charset=utf-8" http-equiv="Content-Type"/>
    <meta content="width=device-width,initial-scale=1.0,user-scalable=yes" name="viewport"/>
    <title>Bustime NYC</title>
    <link media="screen" type="text/css" href="/css/mobile/mobile.css" rel="stylesheet"/>
</head>
<body background="/img/background.jpg">
    <div id="banner">
        <h1>
            <a href="/index"><img src="/img/banner.png" width="100%"/></a>
        </h1>
    </div>
    <div id="searchPanel">
        <form id="index" name="index" action="#" onsubmit="return false;">
            <input value="" placeholder="Enter Stop Code: " class="q" name="q" id="bustimesearch" type="text"/>
            <input alt="search" id="submitButton" class="s" type="submit" onclick="getData();"/>
            <input type="image" src="/img/search_icon.png" class="s"/>
        </form>
    </div>
    <div id="content">
        <?xml version="1.0" encoding="UTF-8"?>
        <div class="busmap">
            <h2><span style="color:white;">"""+busname+""" Bus is</span>&nbsp;
            <span style="color:red">"""+distance+"""</span>&nbsp;<span style="color:white;">Miles Away</span></h2>
            <div id="map"></div>
            <script>
                function initMap() {
                    var myLatLng = {lat: """ + latitude + """, lng: """ + longitude + """};

                    var map = new google.maps.Map(document.getElementById('map'), {
                    zoom: 15,
                    center: myLatLng
                    });

                    var marker = new google.maps.Marker({
                    position: myLatLng,
                    map: map,
                    title: 'Current Location'
                    });

                    var trafficLayer = new google.maps.TrafficLayer();
                    trafficLayer.setMap(map);
                }
            </script>
            <script async defer
                src="https://maps.googleapis.com/maps/api/js?key=AIzaSyDEhlW4EIYyjNSZupr0e3LceHgWHy6zijg&callback=initMap">
            </script>

        </div>
        <div class="sidebar">
            <div class="welcome">
                <h3>Example searches:</h3>
                <ul class="examples">
                    <li><span style="color:white;">Route: </span>&nbsp;B63 M5 Bx1</li>
                    <li><span style="color:white;">Intersection: </span>&nbsp;Main st and Kissena Bl</li>
                    <li><span style="color:white;">Stop Code: </span>&nbsp;200884</li>
                    <li><span style="color:white;">Location: </span>&nbsp;10304</li>
                </ul>
            </div>
        </div>
    </div>
    <div id="footer">
        <p>Help | Contact | <a href="//web.mta.info/default.html">MTA.info</a></p>
    </div>
    <script>
    function getData(){
        var stopNum = document.getElementById('bustimesearch').value;
        var url = 'http://localhost:8000/cgi-bin/bustime.py?StopId='+ stopNum;
        window.open(url, "_self");
    }
    </script>
</body>
</html>

"""
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

latitude = process_data(stop_id, get_data(stop_id, url))[0]
longitude = process_data(stop_id, get_data(stop_id, url))[1]
distance = process_data(stop_id, get_data(stop_id, url))[2]
busname = process_data(stop_id, get_data(stop_id, url))[3]

print "Content-Type: text/html\n\n"

print """
<html>
  <head>
    <title>Bustime NYC</title>
    <style>
    #map {
        width: 500px;
        height: 500px;
        }
    </style>
  </head>
  <body>
    <h3>""" + busname + """ Bus is """ + distance + """ Miles Away</h3>
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
    <p>
    Busname: """ + busname + """<br>
    Latitude: """ + latitude + """<br>
    Longitude: """ + longitude + """<br>
    Distance: """ + distance + """<br>
    </p>
  </body>
</html>
"""
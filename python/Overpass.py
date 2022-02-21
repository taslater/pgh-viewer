import requests
import osm2geojson
import json


class Overpass:
  """
  This class accesses the open street map ('Overpass') API and can optionally return a geoJSON
  """
  def __init__(self):
    self.data = None
    self.SERVER_URL = "http://overpass-api.de/api/interpreter"
    
  def singleQuery(self, area, tag, value, out = "json", timeout = 25, element = "area", geojson = True):
    area = area + 3600000000
    query = f"""
    [out:{out}][timeout:{timeout}];
    area({area})->.myarea;
    (
      {element}[{tag}={value}](area.myarea);
    );
    out geom;
    """
    response = requests.get(url = self.SERVER_URL, params={'data': query})
    self.data = response.text

    if geojson:
      self.data = osm2geojson.json2geojson(self.data)
      return self.data
    else:
      return self.data

  def customQuery(self, query, geojson = True):
    response = requests.get(url = self.SERVER_URL, params={'data': query})
    self.data = response.text

    if geojson:
      self.data = json.loads(self.data)
      self.data = osm2geojson.json2geojson(self.data)
      return self.data
    else:
      return self.data
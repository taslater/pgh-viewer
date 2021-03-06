// import {Circle, Fill, Stroke, Style} from 'ol/style';
const alle_layer = new ol.layer.VectorTile({
  declutter: true,
  source: new ol.source.VectorTile({
    attributions:
      '© <a href="https://www.mapbox.com/map-feedback/">Mapbox</a> ' +
      '© <a href="https://www.openstreetmap.org/copyright">' +
      "OpenStreetMap contributors</a>",
    format: new ol.format.MVT(),
    url: url,
  }),
  // style: createMapboxStreetsV6Style(Style, Fill, Stroke, Icon, Text),
  style: new ol.style.Style({
    fill: new ol.style.Fill({
      color: "rgba(0,0,0,1.0)",
    }),
  }),
});

// console.log(alle_layer)
console.log(alle_layer);

const map = new ol.Map({
  target: "map",
  layers: [
    new ol.layer.Tile({
      source: new ol.source.OSM(),
    }),
    alle_layer,
  ],
  view: new ol.View({
    center: ol.proj.fromLonLat([-79.995888, 40.440624]),
    zoom: 14,
  }),
});

map.on("pointermove", showInfo);
const info = document.getElementById("info");

function showInfo(event) {
  const features = map.getFeaturesAtPixel(event.pixel);
  if (features.length == 0) {
    info.innerText = "";
    info.style.opacity = 0;
    return;
  }
  const properties = features[0].getProperties();
  info.innerText = JSON.stringify(properties, null, 2);
  //console.log(properties);
  info.style.opacity = 1;
}

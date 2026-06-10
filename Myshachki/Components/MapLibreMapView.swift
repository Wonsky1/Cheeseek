import CoreLocation
import SwiftUI
import WebKit

struct MapLibreMapView: UIViewRepresentable {
    private static let readyMessageHandler = "myshachkiReady"

    let center: CLLocationCoordinate2D
    let buildingGeoJSON: String
    let routeGeoJSON: String
    let storageKey: String
    var perspectiveMode: MapPerspectiveMode = .flat
    var styleMode: MapStyleMode = .light
    var showsUserLocation = true
    var fitsRouteBounds = false

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addUserScript(Self.bridgeBootstrapScript)
        configuration.userContentController.add(context.coordinator, name: Self.readyMessageHandler)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://myshachki.local"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let script = """
        window.myshachkiSetData(\(buildingGeoJSON), \(routeGeoJSON), {\(Self.centerJavaScript(center))}, "\(Self.escapedJavaScriptString(storageKey))", { showsUserLocation: \(showsUserLocation), fitsRouteBounds: \(fitsRouteBounds), perspectiveMode: "\(perspectiveMode.rawValue)", styleMode: "\(styleMode.rawValue)" });
        """
        context.coordinator.enqueue(script)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func centerJavaScript(_ center: CLLocationCoordinate2D) -> String {
        "lat: \(center.latitude), lon: \(center.longitude)"
    }

    private static func escapedJavaScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let bridgeBootstrapScript = WKUserScript(
        source: """
        window.myshachkiNativeQueue = window.myshachkiNativeQueue || [];
        window.myshachkiSetData = window.myshachkiSetData || function() {
          window.myshachkiNativeQueue.push(Array.from(arguments));
        };
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="initial-scale=1,maximum-scale=1,user-scalable=no">
      <link href="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.css" rel="stylesheet">
      <script src="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.js"></script>
      <style>
        html, body, #map { width: 100%; height: 100%; margin: 0; padding: 0; background: #14161f; }
        .maplibregl-ctrl-bottom-left, .maplibregl-ctrl-bottom-right { display: none; }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <script>
        const empty = { type: 'FeatureCollection', features: [] };
        const fallbackStyle = {
          version: 8,
          sources: {
            openmaptiles: { type: 'vector', url: 'https://tiles.openfreemap.org/planet' }
          },
          glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
          layers: [
            { id: 'background', type: 'background', paint: { 'background-color': '#f4f1ea' } },
            { id: 'building', type: 'fill', source: 'openmaptiles', 'source-layer': 'building', paint: { 'fill-color': '#e4ddd3', 'fill-opacity': 0.92 } },
            { id: 'building-3d', type: 'fill-extrusion', source: 'openmaptiles', 'source-layer': 'building', minzoom: 15, paint: { 'fill-extrusion-color': '#d9d1c6', 'fill-extrusion-height': ['coalesce', ['get', 'render_height'], ['get', 'height'], 24], 'fill-extrusion-base': ['coalesce', ['get', 'render_min_height'], ['get', 'min_height'], 0], 'fill-extrusion-opacity': 0.78 } },
            { id: 'roads', type: 'line', source: 'openmaptiles', 'source-layer': 'transportation', paint: { 'line-color': '#c9c2b7', 'line-width': ['interpolate', ['linear'], ['zoom'], 12, 0.5, 17, 5] } }
          ]
        };
        const map = new maplibregl.Map({
          container: 'map',
          style: fallbackStyle,
          center: [21.0122, 52.2297],
          zoom: 15.3,
          pitch: 0,
          attributionControl: false
        });

        function currentPerspectiveMode() {
          return pending.options && pending.options.perspectiveMode === 'threeD' ? 'threeD' : 'flat';
        }

        function currentStyleMode() {
          return pending.options && pending.options.styleMode === 'dark' ? 'dark' : 'light';
        }

        function currentPitch() {
          return currentPerspectiveMode() === 'threeD' ? 58 : 0;
        }

        function currentZoom() {
          return currentPerspectiveMode() === 'threeD' ? 16.1 : 15.3;
        }

        function nativeExtrusionOpacity() {
          return currentPerspectiveMode() === 'threeD' ? 0 : 0.76;
        }

        function applyMapPresentation() {
          if (!map.isStyleLoaded()) return;
          const isDark = currentStyleMode() === 'dark';
          for (const layer of map.getStyle().layers || []) {
            if (layer.id.startsWith('myshachki-')) continue;
            const id = layer.id.toLowerCase();
            const sourceLayer = String(layer['source-layer'] || '').toLowerCase();
            try {
              if (layer.type === 'background') {
                  map.setPaintProperty(layer.id, 'background-color', isDark ? '#090b0f' : '#f4f1ea');
              } else if (layer.type === 'fill') {
                if (id.includes('water') || sourceLayer.includes('water')) {
                  map.setPaintProperty(layer.id, 'fill-color', isDark ? '#081521' : '#d8e6ef');
                  map.setPaintProperty(layer.id, 'fill-opacity', 1);
                } else if (id.includes('park') || id.includes('green') || id.includes('landcover') || sourceLayer.includes('landcover')) {
                  map.setPaintProperty(layer.id, 'fill-color', isDark ? '#102016' : '#dce7d4');
                  map.setPaintProperty(layer.id, 'fill-opacity', isDark ? 0.72 : 0.88);
                } else if (id.includes('building') || sourceLayer.includes('building')) {
                  map.setPaintProperty(layer.id, 'fill-color', isDark ? '#252a32' : '#e4ddd3');
                  map.setPaintProperty(layer.id, 'fill-opacity', isDark ? 0.78 : 0.92);
                } else {
                  map.setPaintProperty(layer.id, 'fill-color', isDark ? '#11151b' : '#efe8dd');
                  map.setPaintProperty(layer.id, 'fill-opacity', isDark ? 0.9 : 0.94);
                }
              } else if (layer.type === 'fill-extrusion') {
                map.setPaintProperty(layer.id, 'fill-extrusion-color', isDark ? '#252a32' : '#d9d1c6');
                map.setPaintProperty(layer.id, 'fill-extrusion-opacity', nativeExtrusionOpacity());
              } else if (layer.type === 'line') {
                if (id.includes('highway') || id.includes('major') || id.includes('trunk') || id.includes('primary')) {
                  map.setPaintProperty(layer.id, 'line-color', isDark ? '#a89458' : '#c3b08b');
                  map.setPaintProperty(layer.id, 'line-opacity', isDark ? 0.48 : 0.64);
                } else if (id.includes('road') || sourceLayer.includes('transportation')) {
                  map.setPaintProperty(layer.id, 'line-color', isDark ? '#747d88' : '#c9c2b7');
                  map.setPaintProperty(layer.id, 'line-opacity', isDark ? 0.42 : 0.62);
                } else if (id.includes('rail')) {
                  map.setPaintProperty(layer.id, 'line-color', isDark ? '#4d5662' : '#b8b3ab');
                  map.setPaintProperty(layer.id, 'line-opacity', isDark ? 0.34 : 0.48);
                } else if (id.includes('water')) {
                  map.setPaintProperty(layer.id, 'line-color', isDark ? '#16304a' : '#b3d0dd');
                  map.setPaintProperty(layer.id, 'line-opacity', isDark ? 0.46 : 0.56);
                } else {
                  map.setPaintProperty(layer.id, 'line-color', isDark ? '#3a424d' : '#d2cbc1');
                  map.setPaintProperty(layer.id, 'line-opacity', isDark ? 0.3 : 0.44);
                }
              } else if (layer.type === 'symbol') {
                if (layer.layout && layer.layout['text-field'] !== undefined) {
                  map.setPaintProperty(layer.id, 'text-color', isDark ? '#9aa3af' : '#6e675c');
                  map.setPaintProperty(layer.id, 'text-halo-color', isDark ? '#07090d' : '#f7f2ea');
                  map.setPaintProperty(layer.id, 'text-halo-width', isDark ? 1.2 : 1.1);
                  map.setPaintProperty(layer.id, 'text-opacity', id.includes('poi') ? (isDark ? 0.34 : 0.52) : (isDark ? 0.62 : 0.78));
                }
                if (layer.layout && layer.layout['icon-image'] !== undefined) {
                  map.setPaintProperty(layer.id, 'icon-opacity', isDark ? 0.34 : 0.48);
                }
              }
            } catch (error) {
              reportOnce(`map-style-${layer.id}`, error);
            }
          }

          if (map.getLayer('myshachki-buildings-fill')) {
            map.setPaintProperty('myshachki-buildings-fill', 'fill-color', [
              'match', ['get', 'status'],
              'active', activeFillColor(),
              'explored', exploredFillColor(),
              'rgba(0,0,0,0)'
            ]);
            map.setPaintProperty('myshachki-buildings-fill', 'fill-opacity', currentPerspectiveMode() === 'threeD'
              ? 0
              : [
                  'case',
                  ['==', ['get', 'status'], 'available'], 0,
                  ['==', ['get', 'isFullyCovered'], true], 0.8,
                  0.58
                ]
            );
          }
          if (map.getLayer('myshachki-buildings-outline')) {
            map.setPaintProperty('myshachki-buildings-outline', 'line-color', [
              'match', ['get', 'status'],
              'active', activeOutlineColor(),
              'explored', exploredOutlineColor(),
              '#000000'
            ]);
            map.setPaintProperty('myshachki-buildings-outline', 'line-opacity', currentPerspectiveMode() === 'threeD'
              ? 0
              : ['case', ['==', ['get', 'status'], 'available'], 0, 0.82]
            );
          }
          if (map.getLayer('myshachki-buildings-extrusion')) {
            map.setPaintProperty('myshachki-buildings-extrusion', 'fill-extrusion-color', [
              'match', ['get', 'status'],
              'active', activeFillColor(),
              'explored', exploredFillColor(),
              'rgba(0,0,0,0)'
            ]);
            map.setPaintProperty('myshachki-buildings-extrusion', 'fill-extrusion-opacity', currentPerspectiveMode() === 'threeD' ? 1 : 0);
          }
          if (map.getLayer('myshachki-route-line')) {
            map.setPaintProperty('myshachki-route-line', 'line-color', [
              'match', ['get', 'status'],
              'explored', exploredFillColor(),
              routeLineColor()
            ]);
          }
        }

        let pending = {
          route: empty,
          center: { lat: 52.2297, lon: 21.0122 },
          storageKey: 'anonymous',
          options: { showsUserLocation: true, fitsRouteBounds: false }
        };
        let buildingQueryLayers = ['building-3d', 'building'];
        let buildingQueryRadiusPixels = 30;
        let routeSampleStepPixels = 34;
        let maxRouteSamples = 90;
        let maxSelectedBuildings = 1400;
        let emptyBuildingOverlay = { type: 'FeatureCollection', features: [] };
        let emptyPoint = { type: 'FeatureCollection', features: [] };
        let safeReported = new Set();
        let persistedBuildingFeatures = new Map();
        let activeBuildingFeatures = new Map();
        let processedActiveSegments = new Set();
        let perfCounters = { recomputeCount: 0, lastReportAt: performance.now(), totalRecomputeMs: 0, totalQueryCount: 0, lastSlowReportAt: 0 };
        let perfLoggingEnabled = true;
        let persistedSaveDelayMs = 900;
        let persistedSaveState = { timer: null };
        let coverAnimationState = { frame: null };
        let sourceUpdateState = { routeSignature: '', overlaySignature: '', cameraSignature: '', lastCameraAt: 0 };
        let storagePrefix = 'myshachki.coveredBuildings.v2.';
        let maxPersistedFeatures = 5000;
        let sourceLayerName = 'building';
        let renderedQueryOptions = { layers: buildingQueryLayers };
        let animationDurationMs = 460;
        let animationSourceID = 'myshachki-building-animations';

        function routeLineColor() {
          return currentStyleMode() === 'dark' ? '#5fd9f5' : '#5ab3d6';
        }

        function activeFillColor() {
          return currentStyleMode() === 'dark' ? '#944cff' : '#b852ff';
        }

        function exploredFillColor() {
          return currentStyleMode() === 'dark' ? '#d7a82e' : '#f2c94c';
        }

        function activeOutlineColor() {
          return currentStyleMode() === 'dark' ? '#c090ff' : '#9f46ea';
        }

        function exploredOutlineColor() {
          return currentStyleMode() === 'dark' ? '#e7bc50' : '#ddaf2c';
        }

        let buildingFillPaint = {
          'fill-color': [
            'match', ['get', 'status'],
            'active', '#b852ff',
            'explored', '#f2c94c',
            'rgba(0,0,0,0)'
          ],
          'fill-opacity': [
            'case',
            ['==', ['get', 'status'], 'available'], 0,
            ['==', ['get', 'isFullyCovered'], true], 0.8,
            0.58
          ]
        };
        let buildingOutlinePaint = {
          'line-color': [
            'match', ['get', 'status'],
            'active', '#9f46ea',
            'explored', '#ddaf2c',
            '#000000'
          ],
          'line-opacity': ['case', ['==', ['get', 'status'], 'available'], 0, 0.82],
          'line-width': ['case', ['==', ['get', 'isFullyCovered'], true], 1.45, 1.0]
        };
        let buildingExtrusionPaint = {
          'fill-extrusion-color': [
            'match', ['get', 'status'],
            'active', '#b852ff',
            'explored', '#f2c94c',
            'rgba(0,0,0,0)'
          ],
          'fill-extrusion-height': ['+', ['coalesce', ['get', 'height'], 24], 0.9],
          'fill-extrusion-base': ['coalesce', ['get', 'minHeight'], 0],
          'fill-extrusion-opacity': 0,
          'fill-extrusion-vertical-gradient': false
        };
        let buildingFillLayer = {
          id: 'myshachki-buildings-fill',
          type: 'fill',
          source: 'myshachki-buildings',
          paint: buildingFillPaint
        };
        let buildingExtrusionLayer = {
          id: 'myshachki-buildings-extrusion',
          type: 'fill-extrusion',
          source: 'myshachki-buildings',
          paint: buildingExtrusionPaint
        };
        let buildingAnimationFillLayer = {
          id: 'myshachki-buildings-animation-fill',
          type: 'fill',
          source: animationSourceID,
          paint: {
            'fill-color': [
              'match', ['get', 'status'],
              'active', '#d83cff',
              'explored', '#ffd84f',
              '#ffffff'
            ],
            'fill-opacity': 0
          }
        };
        let buildingAnimationExtrusionLayer = {
          id: 'myshachki-buildings-animation-extrusion',
          type: 'fill-extrusion',
          source: animationSourceID,
          paint: {
            'fill-extrusion-color': [
              'match', ['get', 'status'],
              'active', '#d83cff',
              'explored', '#ffd84f',
              '#ffffff'
            ],
            'fill-extrusion-height': ['+', ['coalesce', ['get', 'height'], 24], 0.9],
            'fill-extrusion-base': ['coalesce', ['get', 'minHeight'], 0],
            'fill-extrusion-opacity': 0,
            'fill-extrusion-vertical-gradient': false
          }
        };
        let buildingOutlineLayer = {
          id: 'myshachki-buildings-outline',
          type: 'line',
          source: 'myshachki-buildings',
          paint: buildingOutlinePaint
        };
        let routeLayer = {
          id: 'myshachki-route-line',
          type: 'line',
          source: 'myshachki-route',
          paint: {
            'line-color': [
              'match', ['get', 'status'],
              'explored', '#f2c94c',
              '#5ab3d6'
            ],
            'line-opacity': [
              'case',
              ['==', ['get', 'status'], 'explored'], 0.26,
              0.86
            ],
            'line-width': [
              'case',
              ['==', ['get', 'status'], 'explored'], 1.8,
              2.8
            ]
          },
          layout: { 'line-cap': 'round', 'line-join': 'round' }
        };
        let userLocationLayer = {
          id: 'myshachki-user-dot',
          type: 'circle',
          source: 'myshachki-user',
          paint: {
            'circle-radius': 8,
            'circle-color': '#0a84ff',
            'circle-stroke-color': '#ffffff',
            'circle-stroke-width': 3,
            'circle-opacity': 0.98
          }
        };
        let userLocationHaloLayer = {
          id: 'myshachki-user-halo',
          type: 'circle',
          source: 'myshachki-user',
          paint: {
            'circle-radius': 18,
            'circle-color': '#0a84ff',
            'circle-opacity': 0.18
          }
        };
        let currentRouteFeatures = () => {
          const features = pending.route && pending.route.features ? pending.route.features : [];
          return features.filter(feature => feature.geometry && feature.geometry.type === 'LineString');
        };
        let recomputeQueued = { value: false };
        let idleRecomputeNeeded = { value: false };
        let exploredReplayAttempts = { value: 0 };
        let maxExploredReplayAttempts = 18;

        function ensureLayers() {
          applyMapPresentation();
          if (!map.getSource('myshachki-buildings')) {
            map.addSource('myshachki-buildings', { type: 'geojson', data: empty });
            map.addLayer(buildingFillLayer);
            map.addLayer(buildingExtrusionLayer);
            map.addLayer(buildingOutlineLayer);
          }
          if (!map.getSource(animationSourceID)) {
            map.addSource(animationSourceID, { type: 'geojson', data: empty });
            map.addLayer(buildingAnimationFillLayer);
            map.addLayer(buildingAnimationExtrusionLayer);
          }
          if (!map.getSource('myshachki-route')) {
            map.addSource('myshachki-route', { type: 'geojson', data: empty });
            map.addLayer(routeLayer);
            sourceUpdateState.routeSignature = '';
          }
          if (!map.getSource('myshachki-user')) {
            map.addSource('myshachki-user', { type: 'geojson', data: emptyPoint });
            map.addLayer(userLocationHaloLayer);
            map.addLayer(userLocationLayer);
          }
        }

        function applyData() {
          if (!map.loaded()) return;
          ensureLayers();
          applyMapPresentation();
          applyRouteSourceData();
          map.getSource('myshachki-user').setData(userLocationFeatureCollection());
          loadPersistedFeaturesIfNeeded();
          applyCachedBuildingOverlay();
          if (pending.options.fitsRouteBounds) {
            fitRouteBounds();
          } else {
            applyCamera();
          }
          idleRecomputeNeeded.value = true;
          scheduleBuildingRecompute();
        }

        function applyCamera() {
          const zoom = currentZoom();
          const pitch = currentPitch();
          const signature = `${Number(pending.center.lon).toFixed(6)},${Number(pending.center.lat).toFixed(6)}:${zoom}:${pitch}`;
          if (sourceUpdateState.cameraSignature === signature) return;
          const now = performance.now();
          const duration = now - sourceUpdateState.lastCameraAt < 220 ? 90 : 180;
          sourceUpdateState.cameraSignature = signature;
          sourceUpdateState.lastCameraAt = now;
          map.stop();
          map.easeTo({
            center: [pending.center.lon, pending.center.lat],
            zoom,
            pitch,
            bearing: 0,
            duration
          });
        }

        function applyRouteSourceData() {
          if (!map.getSource('myshachki-route')) return;
          const signature = routeSignature(pending.route || empty);
          if (sourceUpdateState.routeSignature === signature) return;
          sourceUpdateState.routeSignature = signature;
          map.getSource('myshachki-route').setData(pending.route || empty);
        }

        function routeSignature(route) {
          const features = route && route.features ? route.features : [];
          return features.map(feature => {
            const coordinates = feature.geometry && feature.geometry.coordinates ? feature.geometry.coordinates : [];
            const first = coordinates[0] || [];
            const last = coordinates[coordinates.length - 1] || [];
            const status = feature.properties && feature.properties.status ? feature.properties.status : '';
            return `${status}:${coordinates.length}:${roundedCoordinateKey(first)}:${roundedCoordinateKey(last)}`;
          }).join('|');
        }

        window.myshachkiSetData = function(buildings, route, center, storageKey, options) {
          const nextStorageKey = storageKey || 'anonymous';
          if (nextStorageKey !== pending.storageKey) {
            pending.storageKey = nextStorageKey;
            persistedBuildingFeatures.clear();
            activeBuildingFeatures.clear();
            processedActiveSegments.clear();
            sourceUpdateState.overlaySignature = '';
            exploredReplayAttempts.value = 0;
            loadPersistedFeaturesIfNeeded();
          }
          if (route !== pending.route) {
            exploredReplayAttempts.value = 0;
          }
          pending.route = route || empty;
          pending.center = center || pending.center;
          pending.options = options || pending.options;
          applyData();
        };
        for (const queuedArguments of window.myshachkiNativeQueue || []) {
          window.myshachkiSetData.apply(window, queuedArguments);
        }
        window.myshachkiNativeQueue = [];
        window.webkit.messageHandlers.\(readyMessageHandler).postMessage('ready');

        function scheduleBuildingRecompute() {
          if (recomputeQueued.value) return;
          recomputeQueued.value = true;
          requestAnimationFrame(() => {
            recomputeQueued.value = false;
            recomputeBuildingOverlay();
          });
        }

        function recomputeBuildingOverlay() {
          const startedAt = performance.now();
          if (!map.loaded() || !map.getSource('myshachki-buildings')) return;
          const routeFeatures = currentRouteFeatures();
          if (routeFeatures.every(feature => feature.geometry.coordinates.length < 2)) {
            activeBuildingFeatures.clear();
            processedActiveSegments.clear();
            applyCachedBuildingOverlay();
            return;
          }

          var persistedChanged = false;
          var queryCount = 0;
          const newlyCovered = [];
          const hasActiveRoute = routeFeatures.some(feature => {
            return !(feature.properties && feature.properties.status === 'explored')
              && feature.geometry
              && feature.geometry.coordinates
              && feature.geometry.coordinates.length > 1;
          });
          if (!hasActiveRoute) {
            activeBuildingFeatures.clear();
            processedActiveSegments.clear();
          }
          for (const routeFeature of routeFeatures) {
            const status = routeFeature.properties && routeFeature.properties.status === 'explored' ? 'explored' : 'active';
            const coordinates = routeFeature.geometry.coordinates || [];
            if (coordinates.length < 2) continue;

            if (status === 'explored') {
              if (persistedBuildingFeatures.size > 0) continue;
              const result = processRouteCoordinates(coordinates, status, newlyCovered);
              persistedChanged = persistedChanged || result.persistedChanged;
              queryCount += result.queryCount;
              continue;
            }

            for (const segment of unprocessedActiveSegments(coordinates)) {
              const result = processRouteCoordinates(segment.coordinates, status, newlyCovered);
              persistedChanged = persistedChanged || result.persistedChanged;
              queryCount += result.queryCount;
            }
          }

          if (persistedChanged) {
            exploredReplayAttempts.value = 0;
            schedulePersistedSave();
            playCoverAnimation(newlyCovered);
          } else if (hasReplayableExploredRoutes() && persistedBuildingFeatures.size === 0) {
            exploredReplayAttempts.value += 1;
          }
          applyCachedBuildingOverlay();
          reportPerf(startedAt, queryCount);
        }

        function processRouteCoordinates(coordinates, status, newlyCovered) {
          var persistedChanged = false;
          var queryCount = 0;
          const samples = routeSamples(coordinates);
          for (const sample of samples) {
            const queried = queryRenderedBuildings(sample.x, sample.y, buildingQueryRadiusPixels);
            queryCount += 1;
            for (const feature of queried) {
              if (!isBuildingPolygon(feature)) continue;
              const baseKey = featureKey(feature);
              if (!baseKey) continue;
              for (const part of buildingPolygonParts(feature)) {
                if (!polygonTouchesQueryBox(part.coordinates, sample.x, sample.y, buildingQueryRadiusPixels)) continue;
                const key = `${baseKey}:part:${part.key}`;
                if (!key) continue;
                if (status === 'active' && persistedBuildingFeatures.has(key)) {
                  activeBuildingFeatures.delete(key);
                  continue;
                }
                const candidate = overlayFeature(part.coordinates, key, status, feature);
                if (status === 'active') {
                  activeBuildingFeatures.set(key, candidate);
                }
                if (!persistedBuildingFeatures.has(key)) {
                  persistedBuildingFeatures.set(key, overlayFeature(part.coordinates, key, 'explored', feature));
                  newlyCovered.push(candidate);
                  persistedChanged = true;
                }
              }
            }
          }
          return { persistedChanged, queryCount };
        }

        function unprocessedActiveSegments(coordinates) {
          const segments = [];
          for (let index = Math.max(1, coordinates.length - 4); index < coordinates.length; index += 1) {
            const previous = coordinates[index - 1];
            const current = coordinates[index];
            const key = `${roundedCoordinateKey(previous)}>${roundedCoordinateKey(current)}`;
            if (processedActiveSegments.has(key)) continue;
            processedActiveSegments.add(key);
            segments.push({ key, coordinates: [previous, current] });
          }
          if (processedActiveSegments.size > 700) {
            const recent = new Set(Array.from(processedActiveSegments).slice(-420));
            processedActiveSegments.clear();
            for (const key of recent) processedActiveSegments.add(key);
          }
          return segments;
        }

        function roundedCoordinateKey(coordinate) {
          return `${Number(coordinate[0]).toFixed(6)},${Number(coordinate[1]).toFixed(6)}`;
        }

        function hasReplayableExploredRoutes() {
          return currentRouteFeatures().some(feature => {
            return feature.properties
              && feature.properties.status === 'explored'
              && feature.geometry
              && feature.geometry.coordinates
              && feature.geometry.coordinates.length > 1;
          });
        }

        function applyCachedBuildingOverlay() {
          if (!map.getSource('myshachki-buildings')) return;
          const merged = new Map(persistedBuildingFeatures);
          for (const [key, feature] of activeBuildingFeatures) {
            merged.set(key, feature);
          }
          const features = Array.from(merged.values()).slice(0, maxSelectedBuildings);
          const signature = features.map(feature => {
            const props = feature.properties || {};
            return `${feature.id}:${props.status || ''}:${props.height || ''}:${props.minHeight || ''}`;
          }).join('|');
          if (sourceUpdateState.overlaySignature === signature) return;
          sourceUpdateState.overlaySignature = signature;
          map.getSource('myshachki-buildings').setData({
            type: 'FeatureCollection',
            features
          });
        }

        function loadPersistedFeaturesIfNeeded() {
          if (persistedBuildingFeatures.size > 0) return;
          const stored = localStorage.getItem(storagePrefix + pending.storageKey);
          if (!stored) return;
          try {
            const parsed = JSON.parse(stored);
            const features = parsed && parsed.features ? parsed.features : [];
            for (const feature of features) {
              if (!feature || !feature.id || !feature.geometry) continue;
              feature.properties = Object.assign(
                { height: 24, minHeight: 0 },
                feature.properties || {},
                { status: 'explored', isFullyCovered: true }
              );
              persistedBuildingFeatures.set(String(feature.id), feature);
            }
          } catch (error) {
            reportOnce('load-persisted-buildings', error);
          }
        }

        function savePersistedFeatures() {
          try {
            const features = Array.from(persistedBuildingFeatures.values()).slice(-maxPersistedFeatures);
            localStorage.setItem(storagePrefix + pending.storageKey, JSON.stringify({ type: 'FeatureCollection', features }));
          } catch (error) {
            reportOnce('save-persisted-buildings', error);
          }
        }

        function schedulePersistedSave() {
          if (persistedSaveState.timer !== null) {
            clearTimeout(persistedSaveState.timer);
          }
          persistedSaveState.timer = setTimeout(() => {
            persistedSaveState.timer = null;
            savePersistedFeatures();
          }, persistedSaveDelayMs);
        }

        function playCoverAnimation(features) {
          if (!features || features.length === 0 || !map.getSource(animationSourceID)) return;
          const animationFeatures = features.slice(-42);
          map.getSource(animationSourceID).setData({
            type: 'FeatureCollection',
            features: animationFeatures
          });
          if (coverAnimationState.frame !== null) {
            cancelAnimationFrame(coverAnimationState.frame);
          }
          const startedAt = performance.now();
          const tick = () => {
            const progress = Math.min(1, (performance.now() - startedAt) / animationDurationMs);
            const eased = 1 - Math.pow(1 - progress, 3);
            const fillOpacity = Math.max(0, 0.44 * (1 - eased));
            const extrusionOpacity = currentPerspectiveMode() === 'threeD'
              ? Math.max(0, 0.72 * (1 - eased))
              : 0;
            if (map.getLayer('myshachki-buildings-animation-fill')) {
              map.setPaintProperty('myshachki-buildings-animation-fill', 'fill-opacity', fillOpacity);
            }
            if (map.getLayer('myshachki-buildings-animation-extrusion')) {
              map.setPaintProperty('myshachki-buildings-animation-extrusion', 'fill-extrusion-opacity', extrusionOpacity);
            }
            if (progress < 1) {
              coverAnimationState.frame = requestAnimationFrame(tick);
            } else {
              coverAnimationState.frame = null;
              map.getSource(animationSourceID).setData(empty);
            }
          };
          tick();
        }

        function reportPerf(startedAt, queryCount) {
          if (!perfLoggingEnabled) return;
          const duration = performance.now() - startedAt;
          perfCounters.recomputeCount += 1;
          perfCounters.totalRecomputeMs += duration;
          perfCounters.totalQueryCount += queryCount;
          const now = performance.now();
          if (duration > 32 && now - perfCounters.lastSlowReportAt > 800) {
            perfCounters.lastSlowReportAt = now;
            console.warn(`[myshachki-perf] slow building recompute ${duration.toFixed(1)}ms, queries=${queryCount}, explored=${persistedBuildingFeatures.size}, active=${activeBuildingFeatures.size}`);
          }
          if (now - perfCounters.lastReportAt > 5000) {
            const averageMs = perfCounters.totalRecomputeMs / Math.max(1, perfCounters.recomputeCount);
            const averageQueries = perfCounters.totalQueryCount / Math.max(1, perfCounters.recomputeCount);
            console.warn(`[myshachki-perf] recomputes=${perfCounters.recomputeCount}, avg=${averageMs.toFixed(1)}ms, avgQueries=${averageQueries.toFixed(1)}, explored=${persistedBuildingFeatures.size}`);
            perfCounters.recomputeCount = 0;
            perfCounters.totalRecomputeMs = 0;
            perfCounters.totalQueryCount = 0;
            perfCounters.lastReportAt = now;
          }
        }

        function routeSamples(coordinates) {
          const projected = coordinates.map(coord => map.project(coord));
          const samples = [];
          for (let index = projected.length - 2; index >= 0; index -= 1) {
            const start = projected[index];
            const end = projected[index + 1];
            const dx = end.x - start.x;
            const dy = end.y - start.y;
            const distance = Math.hypot(dx, dy);
            const steps = Math.max(1, Math.ceil(distance / routeSampleStepPixels));
            for (let step = 0; step <= steps; step += 1) {
              const t = step / steps;
              samples.push({ x: start.x + dx * t, y: start.y + dy * t });
              if (samples.length >= maxRouteSamples) return samples;
            }
          }
          return samples;
        }

        function userLocationFeatureCollection() {
          if (!pending.options.showsUserLocation) return emptyPoint;
          return {
            type: 'FeatureCollection',
            features: [{
              type: 'Feature',
              properties: {},
              geometry: {
                type: 'Point',
                coordinates: [pending.center.lon, pending.center.lat]
              }
            }]
          };
        }

        function fitRouteBounds() {
          const coordinates = currentRouteFeatures().flatMap(feature => feature.geometry.coordinates);
          if (coordinates.length < 2) {
            map.easeTo({ center: [pending.center.lon, pending.center.lat], zoom: 15.8, duration: 220 });
            return;
          }
          const bounds = coordinates.reduce((currentBounds, coordinate) => {
            return currentBounds.extend(coordinate);
          }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]));
          map.fitBounds(bounds, {
            padding: { top: 26, bottom: 26, left: 26, right: 26 },
            maxZoom: 17.2,
            duration: 280
          });
        }

        function queryRenderedBuildings(x, y, radius) {
          const bounds = [
            [x - radius, y - radius],
            [x + radius, y + radius]
          ];
          try {
            return map.queryRenderedFeatures(bounds, renderedQueryOptions);
          } catch (error) {
            reportOnce('building-query', error);
            return [];
          }
        }

        function isBuildingPolygon(feature) {
          return feature
            && feature.geometry
            && (feature.geometry.type === 'Polygon' || feature.geometry.type === 'MultiPolygon');
        }

        function buildingPolygonParts(feature) {
          if (feature.geometry.type === 'Polygon') {
            const coordinates = feature.geometry.coordinates;
            return [{ key: hashString(JSON.stringify(coordinates[0] || coordinates)), coordinates }];
          }
          return feature.geometry.coordinates.map((coordinates, index) => ({
            key: `${index}:${hashString(JSON.stringify(coordinates[0] || coordinates))}`,
            coordinates
          }));
        }

        function polygonTouchesQueryBox(coordinates, x, y, radius) {
          let minX = Number.POSITIVE_INFINITY;
          let minY = Number.POSITIVE_INFINITY;
          let maxX = Number.NEGATIVE_INFINITY;
          let maxY = Number.NEGATIVE_INFINITY;
          for (const ring of coordinates) {
            for (const coordinate of ring) {
              const point = map.project(coordinate);
              minX = Math.min(minX, point.x);
              minY = Math.min(minY, point.y);
              maxX = Math.max(maxX, point.x);
              maxY = Math.max(maxY, point.y);
            }
          }
          if (!Number.isFinite(minX) || !Number.isFinite(minY)) return false;
          return maxX >= x - radius && minX <= x + radius && maxY >= y - radius && minY <= y + radius;
        }

        function overlayFeature(coordinates, key, status, sourceFeature) {
          const height = buildingHeight(sourceFeature);
          const minHeight = buildingMinHeight(sourceFeature);
          return {
            type: 'Feature',
            id: key,
            properties: {
              id: key,
              status,
              isFullyCovered: true,
              height,
              minHeight,
              sourceLayer: sourceLayerName
            },
            geometry: {
              type: 'Polygon',
              coordinates
            }
          };
        }

        function buildingHeight(feature) {
          const props = feature && feature.properties ? feature.properties : {};
          const candidates = [
            props.render_height,
            props.height,
            props['building:height']
          ];
          for (const candidate of candidates) {
            const value = numericMapProperty(candidate);
            if (value !== null) return Math.max(8, Math.min(value, 120));
          }
          const levels = numericMapProperty(props.render_min_height ? null : props['building:levels']);
          if (levels !== null) return Math.max(8, Math.min(levels * 3.2, 90));
          return 24;
        }

        function buildingMinHeight(feature) {
          const props = feature && feature.properties ? feature.properties : {};
          const candidates = [
            props.render_min_height,
            props.min_height,
            props['building:min_height']
          ];
          for (const candidate of candidates) {
            const value = numericMapProperty(candidate);
            if (value !== null) return Math.max(0, Math.min(value, 80));
          }
          return 0;
        }

        function numericMapProperty(value) {
          if (value === undefined || value === null || value === '') return null;
          const parsed = Number(String(value).replace(/m$/i, '').trim());
          return Number.isFinite(parsed) ? parsed : null;
        }

        function featureKey(feature) {
          if (feature.id !== undefined && feature.id !== null) {
            return `${feature.sourceLayer || sourceLayerName}:${feature.id}`;
          }
          const props = feature.properties || {};
          const possiblePropertyID = props.id || props.osm_id || props['@id'];
          if (possiblePropertyID !== undefined && possiblePropertyID !== null) {
            return `${feature.sourceLayer || sourceLayerName}:${possiblePropertyID}`;
          }
          if (!feature.geometry) return null;
          return `${feature.sourceLayer || sourceLayerName}:${hashString(JSON.stringify(feature.geometry.coordinates))}`;
        }

        function hashString(value) {
          let hash = 2166136261;
          for (let index = 0; index < value.length; index += 1) {
            hash ^= value.charCodeAt(index);
            hash = Math.imul(hash, 16777619);
          }
          return (hash >>> 0).toString(16);
        }

        function reportOnce(key, error) {
          if (safeReported.has(key)) return;
          safeReported.add(key);
          console.warn(key, error);
        }

        map.on('load', () => {
          applyMapPresentation();
          applyData();
        });
        map.on('styledata', () => {
          if (!map.isStyleLoaded()) return;
          sourceUpdateState.routeSignature = '';
          sourceUpdateState.overlaySignature = '';
          applyMapPresentation();
          applyData();
        });
        map.on('idle', () => {
          const shouldRetryExploredReplay = hasReplayableExploredRoutes()
            && persistedBuildingFeatures.size === 0
            && exploredReplayAttempts.value < maxExploredReplayAttempts;
          if (!idleRecomputeNeeded.value && !shouldRetryExploredReplay) return;
          idleRecomputeNeeded.value = false;
          scheduleBuildingRecompute();
        });
      </script>
    </body>
    </html>
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingScript: String?
        private var lastEvaluatedScript: String?
        private var isJavaScriptReady = false

        func attach(to webView: WKWebView) {
            self.webView = webView
        }

        func enqueue(_ script: String) {
            if isJavaScriptReady, lastEvaluatedScript == script {
                return
            }
            pendingScript = script
            flushPendingScriptIfReady()
        }

        func flushPendingScriptIfReady() {
            guard isJavaScriptReady, let webView, let pendingScript else { return }
            if lastEvaluatedScript == pendingScript {
                self.pendingScript = nil
                return
            }
            lastEvaluatedScript = pendingScript
            self.pendingScript = nil
            webView.evaluateJavaScript(pendingScript)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isJavaScriptReady = false
            lastEvaluatedScript = nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == MapLibreMapView.readyMessageHandler else { return }
            isJavaScriptReady = true
            flushPendingScriptIfReady()
        }
    }
}

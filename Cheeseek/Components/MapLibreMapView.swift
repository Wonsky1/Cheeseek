import CoreLocation
import SwiftUI
import WebKit

struct MapLibreMapView: UIViewRepresentable {
    private static let readyMessageHandler = "cheeseekReady"
    private static let mapInteractionMessageHandler = "cheeseekMapInteraction"
    private static let coverageMessageHandler = "cheeseekCoverage"

    let center: CLLocationCoordinate2D
    let buildingGeoJSON: String
    let routeGeoJSON: String
    let storageKey: String
    var userCoordinate: CLLocationCoordinate2D?
    var perspectiveMode: MapPerspectiveMode = .flat
    var styleMode: MapStyleMode = .light
    var showsUserLocation = true
    var smoothUserLocation = true
    var fitsRouteBounds = false
    var fitToken = 0
    var persistsCoverage = true
    var onCurrentCoverageChange: ((String) -> Void)?
    var onUserInteraction: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addUserScript(Self.bridgeBootstrapScript)
        configuration.userContentController.add(context.coordinator, name: Self.readyMessageHandler)
        configuration.userContentController.add(context.coordinator, name: Self.mapInteractionMessageHandler)
        configuration.userContentController.add(context.coordinator, name: Self.coverageMessageHandler)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://cheeseek.local"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let script = """
        window.cheeseekSetData(\(buildingGeoJSON), \(routeGeoJSON), {\(Self.centerJavaScript(center))}, "\(Self.escapedJavaScriptString(storageKey))", { showsUserLocation: \(showsUserLocation), smoothUserLocation: \(smoothUserLocation), fitsRouteBounds: \(fitsRouteBounds), fitToken: \(fitToken), persistsCoverage: \(persistsCoverage), perspectiveMode: "\(perspectiveMode.rawValue)", styleMode: "\(styleMode.rawValue)", userLocation: \(Self.optionalCoordinateJavaScript(userCoordinate)) });
        """
        context.coordinator.onCurrentCoverageChange = onCurrentCoverageChange
        context.coordinator.onUserInteraction = onUserInteraction
        context.coordinator.enqueue(script)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: readyMessageHandler)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: mapInteractionMessageHandler)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: coverageMessageHandler)
    }

    private static func centerJavaScript(_ center: CLLocationCoordinate2D) -> String {
        "lat: \(center.latitude), lon: \(center.longitude)"
    }

    private static func optionalCoordinateJavaScript(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "null" }
        return "{ lat: \(coordinate.latitude), lon: \(coordinate.longitude) }"
    }

    private static func escapedJavaScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let bridgeBootstrapScript = WKUserScript(
        source: """
        window.cheeseekNativeQueue = window.cheeseekNativeQueue || [];
        window.cheeseekSetData = window.cheeseekSetData || function() {
          window.cheeseekNativeQueue.push(Array.from(arguments));
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
        #summaryOverlay { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; overflow: visible; }
        .maplibregl-ctrl-bottom-left, .maplibregl-ctrl-bottom-right { display: none; }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <svg id="summaryOverlay" aria-hidden="true"></svg>
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
        const summaryOverlay = document.getElementById('summaryOverlay');
        function notifyNativeMapInteraction() {
          window.webkit.messageHandlers.\(mapInteractionMessageHandler).postMessage('user');
        }
        map.on('dragstart', notifyNativeMapInteraction);

        function currentPerspectiveMode() {
          return pending.options && pending.options.perspectiveMode === 'threeD' ? 'threeD' : 'flat';
        }

        function currentStyleMode() {
          return pending.options && pending.options.styleMode === 'dark' ? 'dark' : 'light';
        }

        function currentPitch() {
          if (pending.options.fitsRouteBounds) return 0;
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
            if (layer.id.startsWith('cheeseek-')) continue;
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

          if (map.getLayer('cheeseek-buildings-fill')) {
            map.setPaintProperty('cheeseek-buildings-fill', 'fill-color', [
              'match', ['get', 'status'],
              'active', activeFillColor(),
              'explored', exploredFillColor(),
              'rgba(0,0,0,0)'
            ]);
            map.setPaintProperty('cheeseek-buildings-fill', 'fill-opacity', currentPerspectiveMode() === 'threeD'
              ? 0
              : [
                  'case',
                  ['==', ['get', 'status'], 'available'], 0,
                  ['==', ['get', 'isFullyCovered'], true], 0.8,
                  0.58
                ]
            );
          }
          if (map.getLayer('cheeseek-buildings-outline')) {
            map.setPaintProperty('cheeseek-buildings-outline', 'line-color', [
              'match', ['get', 'status'],
              'active', activeOutlineColor(),
              'explored', exploredOutlineColor(),
              '#000000'
            ]);
            map.setPaintProperty('cheeseek-buildings-outline', 'line-opacity', currentPerspectiveMode() === 'threeD'
              ? 0
              : ['case', ['==', ['get', 'status'], 'available'], 0, 0.82]
            );
          }
          if (map.getLayer('cheeseek-buildings-extrusion')) {
            map.setPaintProperty('cheeseek-buildings-extrusion', 'fill-extrusion-color', [
              'match', ['get', 'status'],
              'active', activeFillColor(),
              'explored', exploredFillColor(),
              'rgba(0,0,0,0)'
            ]);
            map.setPaintProperty('cheeseek-buildings-extrusion', 'fill-extrusion-opacity', currentPerspectiveMode() === 'threeD' ? 1 : 0);
          }
          if (map.getLayer('cheeseek-available-buildings-extrusion')) {
            map.setPaintProperty('cheeseek-available-buildings-extrusion', 'fill-extrusion-color', availableExtrusionColor());
            map.setPaintProperty('cheeseek-available-buildings-extrusion', 'fill-extrusion-opacity', currentPerspectiveMode() === 'threeD' ? 0.54 : 0);
          }
          if (map.getLayer('cheeseek-route-line')) {
            map.setPaintProperty('cheeseek-route-line', 'line-color', [
              'match', ['get', 'status'],
              'summary', routeLineColor(),
              'explored', exploredFillColor(),
              routeLineColor()
            ]);
            map.setPaintProperty('cheeseek-route-line', 'line-opacity', [
              'match', ['get', 'status'],
              'summary', 0.96,
              'explored', 0.34,
              0.86
            ]);
            map.setPaintProperty('cheeseek-route-line', 'line-width', [
              'match', ['get', 'status'],
              'summary', 5.2,
              'explored', 2.2,
              3.2
            ]);
          }
        }

        let pending = {
          buildings: empty,
          route: empty,
          center: { lat: 52.2297, lon: 21.0122 },
          userLocation: null,
          storageKey: 'anonymous',
          options: { showsUserLocation: true, smoothUserLocation: true, fitsRouteBounds: false }
        };
        let buildingQueryLayers = ['building'];
        let buildingQueryRadiusPixels = 30;
        let routeSampleStepPixels = 34;
        let maxRouteSamples = 90;
        let maxSelectedBuildings = 1400;
        let emptyBuildingOverlay = { type: 'FeatureCollection', features: [] };
        let emptyPoint = { type: 'FeatureCollection', features: [] };
        let safeReported = new Set();
        let availableBuildingFeatures = new Map();
        let persistedBuildingFeatures = new Map();
        let activeBuildingFeatures = new Map();
        let currentWalkBuildingKeys = new Set();
        let processedActiveSegments = new Set();
        let perfCounters = { recomputeCount: 0, lastReportAt: performance.now(), totalRecomputeMs: 0, totalQueryCount: 0, lastSlowReportAt: 0 };
        let perfLoggingEnabled = true;
        let persistedSaveDelayMs = 900;
        let persistedSaveState = { timer: null };
        let coverAnimationState = { frame: null };
        let userAnimationState = { frame: null, coordinate: null, lastTargetAt: 0 };
        let sourceUpdateState = { routeSignature: '', overlaySignature: '', availableOverlaySignature: '', cameraSignature: '', lastCameraAt: 0 };
        let currentCoveragePostState = { signature: '' };
        let storagePrefix = 'cheeseek.coveredBuildings.v2.';
        let maxPersistedFeatures = 5000;
        let sourceLayerName = 'building';
        let renderedQueryOptions = { layers: buildingQueryLayers };
        let availableBuildingQueryOptions = { layers: ['building'] };
        let maxAvailableBuildings = 1800;
        let availableQueryPaddingPixels = 90;
        let availableQueryState = { signature: '', tileRevision: 0, lastTileInvalidationAt: 0 };
        let animationDurationMs = 460;
        let animationSourceID = 'cheeseek-building-animations';

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

        function availableFillColor() {
          return currentStyleMode() === 'dark' ? '#424851' : '#b7b2aa';
        }

        function availableExtrusionColor() {
          return currentStyleMode() === 'dark' ? '#3a4048' : '#aaa49b';
        }

        function availableOutlineColor() {
          return currentStyleMode() === 'dark' ? '#5a626e' : '#8f887d';
        }

        let buildingFillPaint = {
          'fill-color': [
            'match', ['get', 'status'],
            'active', '#b852ff',
            'explored', '#f2c94c',
            'available', '#b7b2aa',
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
            'available', '#8f887d',
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
            'available', '#aaa49b',
            'rgba(0,0,0,0)'
          ],
          'fill-extrusion-height': [
            '+',
            ['coalesce', ['get', 'height'], 24],
            ['match', ['get', 'status'], 'active', 1.8, 'explored', 1.2, 0.6]
          ],
          'fill-extrusion-base': ['coalesce', ['get', 'minHeight'], 0],
          'fill-extrusion-opacity': 0,
          'fill-extrusion-vertical-gradient': false
        };
        let buildingFillLayer = {
          id: 'cheeseek-buildings-fill',
          type: 'fill',
          source: 'cheeseek-buildings',
          paint: buildingFillPaint
        };
        let buildingExtrusionLayer = {
          id: 'cheeseek-buildings-extrusion',
          type: 'fill-extrusion',
          source: 'cheeseek-buildings',
          paint: buildingExtrusionPaint
        };
        let availableBuildingExtrusionLayer = {
          id: 'cheeseek-available-buildings-extrusion',
          type: 'fill-extrusion',
          source: 'cheeseek-available-buildings',
          paint: {
            'fill-extrusion-color': '#aaa49b',
            'fill-extrusion-height': ['+', ['coalesce', ['get', 'height'], 24], 0.35],
            'fill-extrusion-base': ['coalesce', ['get', 'minHeight'], 0],
            'fill-extrusion-opacity': 0,
            'fill-extrusion-vertical-gradient': false
          }
        };
        let buildingAnimationFillLayer = {
          id: 'cheeseek-buildings-animation-fill',
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
          id: 'cheeseek-buildings-animation-extrusion',
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
          id: 'cheeseek-buildings-outline',
          type: 'line',
          source: 'cheeseek-buildings',
          paint: buildingOutlinePaint
        };
        let routeLayer = {
          id: 'cheeseek-route-line',
          type: 'line',
          source: 'cheeseek-route',
          paint: {
            'line-color': [
              'match', ['get', 'status'],
              'summary', '#5ab3d6',
              'explored', '#f2c94c',
              '#5ab3d6'
            ],
            'line-opacity': [
              'match', ['get', 'status'],
              'summary', 0.96,
              'explored', 0.34,
              0.86
            ],
            'line-width': [
              'match', ['get', 'status'],
              'summary', 5.2,
              'explored', 2.2,
              3.2
            ]
          },
          layout: { 'line-cap': 'round', 'line-join': 'round' }
        };
        let userLocationLayer = {
          id: 'cheeseek-user-dot',
          type: 'circle',
          source: 'cheeseek-user',
          paint: {
            'circle-radius': 8,
            'circle-color': '#0a84ff',
            'circle-stroke-color': '#ffffff',
            'circle-stroke-width': 3,
            'circle-opacity': 0.98
          }
        };
        let userLocationHaloLayer = {
          id: 'cheeseek-user-halo',
          type: 'circle',
          source: 'cheeseek-user',
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
          if (!map.getSource('cheeseek-available-buildings')) {
            map.addSource('cheeseek-available-buildings', { type: 'geojson', data: empty });
            map.addLayer(availableBuildingExtrusionLayer);
            sourceUpdateState.availableOverlaySignature = '';
          }
          if (!map.getSource('cheeseek-buildings')) {
            map.addSource('cheeseek-buildings', { type: 'geojson', data: empty });
            map.addLayer(buildingFillLayer);
            map.addLayer(buildingExtrusionLayer);
            map.addLayer(buildingOutlineLayer);
          }
          if (!map.getSource(animationSourceID)) {
            map.addSource(animationSourceID, { type: 'geojson', data: empty });
            map.addLayer(buildingAnimationFillLayer);
            map.addLayer(buildingAnimationExtrusionLayer);
          }
          if (!map.getSource('cheeseek-route')) {
            map.addSource('cheeseek-route', { type: 'geojson', data: empty });
            map.addLayer(routeLayer);
            sourceUpdateState.routeSignature = '';
          }
          if (!map.getSource('cheeseek-user')) {
            map.addSource('cheeseek-user', { type: 'geojson', data: emptyPoint });
            map.addLayer(userLocationHaloLayer);
            map.addLayer(userLocationLayer);
          }
          if (map.getLayer('cheeseek-route-line')) {
            try {
              map.moveLayer('cheeseek-route-line');
            } catch (error) {
              reportOnce('route-layer-order', error);
            }
          }
        }

        function applyData() {
          if (!map.loaded()) return;
          ensureLayers();
          applyMapPresentation();
          const routeChanged = applyRouteSourceData();
          updateUserLocationSource();
          loadPersistedFeaturesIfNeeded();
          applyPreloadedBuildingFeatures();
          applyCachedBuildingOverlay();
          if (pending.options.fitsRouteBounds) {
            fitRouteBounds(routeChanged);
            scheduleSummaryRefreshes(routeChanged);
            scheduleRouteBoundsRefit();
          } else {
            applyCamera();
          }
          renderSummaryOverlay();
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
          if (!map.getSource('cheeseek-route')) return false;
          const signature = routeSignature(pending.route || empty);
          if (sourceUpdateState.routeSignature === signature) return false;
          sourceUpdateState.routeSignature = signature;
          map.getSource('cheeseek-route').setData(pending.route || empty);
          return true;
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

        window.cheeseekSetData = function(buildings, route, center, storageKey, options) {
          pending.options = options || pending.options;
          const nextRoute = route || empty;
          if (nextRoute !== pending.route) {
            exploredReplayAttempts.value = 0;
          }
          pending.buildings = buildings || empty;
          pending.route = nextRoute;
          pending.center = center || pending.center;
          pending.userLocation = pending.options.userLocation || null;
          const nextStorageKey = storageKey || 'anonymous';
          if (nextStorageKey !== pending.storageKey) {
            pending.storageKey = nextStorageKey;
            persistedBuildingFeatures.clear();
            availableBuildingFeatures.clear();
            activeBuildingFeatures.clear();
            currentWalkBuildingKeys.clear();
            processedActiveSegments.clear();
            availableQueryState.signature = '';
            availableQueryState.tileRevision += 1;
            sourceUpdateState.overlaySignature = '';
            sourceUpdateState.availableOverlaySignature = '';
            exploredReplayAttempts.value = 0;
            loadPersistedFeaturesIfNeeded();
          }
          applyData();
        };
        for (const queuedArguments of window.cheeseekNativeQueue || []) {
          window.cheeseekSetData.apply(window, queuedArguments);
        }
        window.cheeseekNativeQueue = [];
        window.webkit.messageHandlers.\(readyMessageHandler).postMessage('ready');

        function scheduleBuildingRecompute() {
          if (recomputeQueued.value) return;
          recomputeQueued.value = true;
          requestAnimationFrame(() => {
            recomputeQueued.value = false;
            recomputeBuildingOverlay();
          });
        }

        function scheduleSummaryRefreshes(routeChanged) {
          if (!pending.options.fitsRouteBounds) return;
          const delays = routeChanged ? [120, 420, 900] : [360];
          for (const delay of delays) {
            setTimeout(() => {
              if (!pending.options.fitsRouteBounds) return;
              fitRouteBounds(false);
              idleRecomputeNeeded.value = true;
              sourceUpdateState.availableOverlaySignature = '';
              renderSummaryOverlay();
              scheduleBuildingRecompute();
            }, delay);
          }
        }

        function recomputeBuildingOverlay() {
          const startedAt = performance.now();
          if (!map.loaded() || !map.getSource('cheeseek-buildings')) return;
          const availableQueryCount = refreshAvailableBuildingsIfNeeded();
          applyAvailableBuildingOverlay();
          const routeFeatures = currentRouteFeatures();
          if (routeFeatures.every(feature => feature.geometry.coordinates.length < 2)) {
            activeBuildingFeatures.clear();
            currentWalkBuildingKeys.clear();
            processedActiveSegments.clear();
            applyCachedBuildingOverlay();
            applyAvailableBuildingOverlay();
            reportPerf(startedAt, availableQueryCount);
            return;
          }

          var persistedChanged = false;
          var queryCount = availableQueryCount;
          const newlyCovered = [];
          const hasActiveRoute = routeFeatures.some(feature => {
            return !(feature.properties && feature.properties.status === 'explored')
              && feature.geometry
              && feature.geometry.coordinates
              && feature.geometry.coordinates.length > 1;
          });
          if (!hasActiveRoute) {
            activeBuildingFeatures.clear();
            currentWalkBuildingKeys.clear();
            processedActiveSegments.clear();
          }
          for (const routeFeature of routeFeatures) {
            const rawStatus = routeFeature.properties && routeFeature.properties.status ? routeFeature.properties.status : '';
            const status = rawStatus === 'explored' ? 'explored' : 'active';
            const coordinates = routeFeature.geometry.coordinates || [];
            if (coordinates.length < 2) continue;

            if (status === 'explored') {
              if (persistedBuildingFeatures.size > 0) continue;
              const result = processRouteCoordinates(coordinates, status, newlyCovered);
              persistedChanged = persistedChanged || result.persistedChanged;
              queryCount += result.queryCount;
              continue;
            }

            if (rawStatus === 'summary') {
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
          applyAvailableBuildingOverlay();
          renderSummaryOverlay();
          reportPerf(startedAt, queryCount);
        }

        function renderSummaryOverlay() {
          if (!summaryOverlay) return;
          if (!pending.options.fitsRouteBounds) {
            summaryOverlay.replaceChildren();
            summaryOverlay.style.display = 'none';
            return;
          }
          summaryOverlay.style.display = 'block';
          const canvas = map.getCanvas();
          summaryOverlay.setAttribute('viewBox', `0 0 ${canvas.clientWidth} ${canvas.clientHeight}`);
          summaryOverlay.replaceChildren();

          const buildingFeatures = summaryBuildingFeatures();
          for (const feature of buildingFeatures) {
            appendSummaryBuilding(feature);
          }

          for (const routeFeature of currentRouteFeatures()) {
            appendSummaryRoute(routeFeature);
          }
        }

        function summaryBuildingFeatures() {
          const merged = new Map();
          const preloaded = pending.buildings && pending.buildings.features ? pending.buildings.features : [];
          for (const feature of preloaded) {
            if (feature && feature.id && feature.geometry) merged.set(String(feature.id), feature);
          }
          for (const [key, feature] of persistedBuildingFeatures) merged.set(key, feature);
          for (const [key, feature] of activeBuildingFeatures) merged.set(key, feature);
          return Array.from(merged.values()).slice(-240);
        }

        function appendSummaryBuilding(feature) {
          const polygons = feature.geometry.type === 'Polygon'
            ? [feature.geometry.coordinates]
            : feature.geometry.type === 'MultiPolygon'
              ? feature.geometry.coordinates
              : [];
          const status = feature.properties && feature.properties.status === 'explored' ? 'explored' : 'active';
          for (const coordinates of polygons) {
            const ring = coordinates[0] || [];
            const points = ring.map(coordinate => {
              const point = map.project(coordinate);
              return `${point.x.toFixed(1)},${point.y.toFixed(1)}`;
            }).join(' ');
            if (!points) continue;
            const polygon = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
            polygon.setAttribute('points', points);
            polygon.setAttribute('fill', status === 'explored' ? exploredFillColor() : activeFillColor());
            polygon.setAttribute('fill-opacity', status === 'explored' ? '0.72' : '0.78');
            polygon.setAttribute('stroke', status === 'explored' ? exploredOutlineColor() : activeOutlineColor());
            polygon.setAttribute('stroke-opacity', '0.9');
            polygon.setAttribute('stroke-width', '1.2');
            summaryOverlay.appendChild(polygon);
          }
        }

        function appendSummaryRoute(routeFeature) {
          const coordinates = routeFeature.geometry && routeFeature.geometry.coordinates ? routeFeature.geometry.coordinates : [];
          if (coordinates.length < 2) return;
          const points = coordinates.map(coordinate => {
            const point = map.project(coordinate);
            return `${point.x.toFixed(1)},${point.y.toFixed(1)}`;
          }).join(' ');
          const polyline = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
          polyline.setAttribute('points', points);
          polyline.setAttribute('fill', 'none');
          polyline.setAttribute('stroke', routeLineColor());
          polyline.setAttribute('stroke-opacity', '0.98');
          polyline.setAttribute('stroke-width', '5.2');
          polyline.setAttribute('stroke-linecap', 'round');
          polyline.setAttribute('stroke-linejoin', 'round');
          summaryOverlay.appendChild(polyline);
        }

        function applyPreloadedBuildingFeatures() {
          const features = pending.buildings && pending.buildings.features ? pending.buildings.features : [];
          if (features.length === 0) return;
          for (const feature of features) {
            if (!feature || !feature.id || !feature.geometry) continue;
            const status = feature.properties && feature.properties.status === 'explored' ? 'explored' : 'active';
            feature.properties = Object.assign(
              { height: 20, minHeight: 0 },
              feature.properties || {},
              { status, isFullyCovered: true }
            );
            const key = String(feature.id);
            if (status === 'explored') {
              persistedBuildingFeatures.set(key, feature);
            } else {
              activeBuildingFeatures.set(key, feature);
              currentWalkBuildingKeys.add(key);
              if (!persistedBuildingFeatures.has(key)
                  && !(pending.options && pending.options.persistsCoverage === false)
                  && !(pending.options && pending.options.fitsRouteBounds)) {
                persistedBuildingFeatures.set(key, Object.assign({}, feature, {
                  properties: Object.assign({}, feature.properties, { status: 'explored' })
                }));
              }
            }
          }
          sourceUpdateState.overlaySignature = '';
        }

        function processRouteCoordinates(coordinates, status, newlyCovered, options = {}) {
          var persistedChanged = false;
          var queryCount = 0;
          const shouldPersistNewCoverage = options.persistNewCoverage !== false
            && !(pending.options && pending.options.persistsCoverage === false);
          const activeOverridesPersisted = options.activeOverridesPersisted === true;
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
                if (status === 'active'
                    && persistedBuildingFeatures.has(key)
                    && !currentWalkBuildingKeys.has(key)
                    && !activeOverridesPersisted) {
                  activeBuildingFeatures.delete(key);
                  continue;
                }
                const candidate = overlayFeature(part.coordinates, key, status, feature);
                if (status === 'active') {
                  activeBuildingFeatures.set(key, candidate);
                }
                if (!persistedBuildingFeatures.has(key)) {
                  if (status === 'active') {
                    currentWalkBuildingKeys.add(key);
                  }
                  if (shouldPersistNewCoverage) {
                    persistedBuildingFeatures.set(key, overlayFeature(part.coordinates, key, 'explored', feature));
                    newlyCovered.push(candidate);
                    persistedChanged = true;
                  }
                } else if (status === 'active' && activeOverridesPersisted) {
                  currentWalkBuildingKeys.add(key);
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
          if (!map.getSource('cheeseek-buildings')) return;
          const merged = new Map(persistedBuildingFeatures);
          for (const [key, feature] of activeBuildingFeatures) {
            merged.set(key, feature);
          }
          const features = Array.from(merged.values()).slice(-maxSelectedBuildings);
          const signature = features.map(feature => {
            const props = feature.properties || {};
            return `${feature.id}:${props.status || ''}:${props.height || ''}:${props.minHeight || ''}`;
          }).join('|');
          postCurrentCoverageIfNeeded(features, signature);
          if (sourceUpdateState.overlaySignature === signature) return;
          sourceUpdateState.overlaySignature = signature;
          map.getSource('cheeseek-buildings').setData({
            type: 'FeatureCollection',
            features
          });
        }

        function postCurrentCoverageIfNeeded(features, signature) {
          if (pending.options && pending.options.fitsRouteBounds) return;
          if (currentCoveragePostState.signature === signature) return;
          currentCoveragePostState.signature = signature;
          try {
            window.webkit.messageHandlers.\(coverageMessageHandler).postMessage(JSON.stringify({
              type: 'FeatureCollection',
              features
            }));
          } catch (error) {
            reportOnce('post-current-coverage', error);
          }
        }

        function applyAvailableBuildingOverlay() {
          if (!map.getSource('cheeseek-available-buildings')) return;
          const features = [];
          if (currentPerspectiveMode() === 'threeD') {
            for (const [key, feature] of availableBuildingFeatures) {
              if (persistedBuildingFeatures.has(key) || activeBuildingFeatures.has(key)) continue;
              features.push(feature);
              if (features.length >= maxAvailableBuildings) break;
            }
          }
          const signature = features.map(feature => {
            const props = feature.properties || {};
            return `${feature.id}:${props.height || ''}:${props.minHeight || ''}`;
          }).join('|');
          if (sourceUpdateState.availableOverlaySignature === signature) return;
          sourceUpdateState.availableOverlaySignature = signature;
          map.getSource('cheeseek-available-buildings').setData({
            type: 'FeatureCollection',
            features
          });
        }

        function refreshAvailableBuildingsIfNeeded() {
          if (currentPerspectiveMode() !== 'threeD') {
            if (availableBuildingFeatures.size > 0) {
              availableBuildingFeatures.clear();
              availableQueryState.signature = '';
              sourceUpdateState.availableOverlaySignature = '';
            }
            return 0;
          }
          if (!map.loaded() || !map.getLayer('building')) return 0;
          const canvas = map.getCanvas();
          const center = map.getCenter();
          const signature = [
            center.lng.toFixed(4),
            center.lat.toFixed(4),
            map.getZoom().toFixed(1),
            map.getPitch().toFixed(0),
            availableQueryState.tileRevision,
            Math.round(canvas.clientWidth / 80),
            Math.round(canvas.clientHeight / 80)
          ].join(':');
          if (availableQueryState.signature === signature && availableBuildingFeatures.size > 0) return 0;
          availableQueryState.signature = signature;
          availableBuildingFeatures.clear();
          const bounds = [
            [-availableQueryPaddingPixels, -availableQueryPaddingPixels],
            [canvas.clientWidth + availableQueryPaddingPixels, canvas.clientHeight + availableQueryPaddingPixels]
          ];
          let queried = [];
          try {
            queried = map.queryRenderedFeatures(bounds, availableBuildingQueryOptions);
          } catch (error) {
            reportOnce('available-building-query', error);
            return 0;
          }
          const centerPoint = { x: canvas.clientWidth / 2, y: canvas.clientHeight / 2 };
          const candidates = [];
          for (const feature of queried) {
            if (!isBuildingPolygon(feature)) continue;
            const baseKey = featureKey(feature);
            if (!baseKey) continue;
            for (const part of buildingPolygonParts(feature)) {
              const key = `${baseKey}:part:${part.key}`;
              if (persistedBuildingFeatures.has(key) || activeBuildingFeatures.has(key)) continue;
              candidates.push({
                key,
                distance: polygonScreenDistanceSq(part.coordinates, centerPoint.x, centerPoint.y),
                feature: overlayFeature(part.coordinates, key, 'available', feature)
              });
            }
          }
          candidates
            .sort((left, right) => left.distance - right.distance)
            .slice(0, maxAvailableBuildings)
            .forEach(candidate => {
              availableBuildingFeatures.set(candidate.key, candidate.feature);
            });
          sourceUpdateState.availableOverlaySignature = '';
          return 1;
        }

        function loadPersistedFeaturesIfNeeded() {
          if (pending.options && pending.options.persistsCoverage === false) {
            const hasPreloadedBuildings = pending.buildings
              && pending.buildings.features
              && pending.buildings.features.length > 0;
            if (!pending.options.fitsRouteBounds || hasPreloadedBuildings) return;
          }
          if (persistedBuildingFeatures.size > 0) return;
          const stored = localStorage.getItem(storagePrefix + pending.storageKey);
          if (!stored) return;
          try {
            const parsed = JSON.parse(stored);
            const features = parsed && parsed.features ? parsed.features : [];
            for (const feature of features) {
              if (!feature || !feature.id || !feature.geometry) continue;
              const baseKey = overlayBaseKey(feature);
              feature.properties = Object.assign(
                { height: 24, minHeight: 0, baseKey },
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
          if (pending.options && pending.options.persistsCoverage === false) return;
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
          if (currentPerspectiveMode() === 'threeD') return;
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
            if (map.getLayer('cheeseek-buildings-animation-fill')) {
              map.setPaintProperty('cheeseek-buildings-animation-fill', 'fill-opacity', fillOpacity);
            }
            if (map.getLayer('cheeseek-buildings-animation-extrusion')) {
              map.setPaintProperty('cheeseek-buildings-animation-extrusion', 'fill-extrusion-opacity', extrusionOpacity);
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
            console.warn(`[cheeseek-perf] slow building recompute ${duration.toFixed(1)}ms, queries=${queryCount}, explored=${persistedBuildingFeatures.size}, active=${activeBuildingFeatures.size}`);
          }
          if (now - perfCounters.lastReportAt > 5000) {
            const averageMs = perfCounters.totalRecomputeMs / Math.max(1, perfCounters.recomputeCount);
            const averageQueries = perfCounters.totalQueryCount / Math.max(1, perfCounters.recomputeCount);
            console.warn(`[cheeseek-perf] recomputes=${perfCounters.recomputeCount}, avg=${averageMs.toFixed(1)}ms, avgQueries=${averageQueries.toFixed(1)}, explored=${persistedBuildingFeatures.size}`);
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
          if (!pending.options.showsUserLocation || !pending.userLocation) return emptyPoint;
          return userLocationFeatureCollectionFor(pending.userLocation);
        }

        function userLocationFeatureCollectionFor(location) {
          if (!location) return emptyPoint;
          return {
            type: 'FeatureCollection',
            features: [{
              type: 'Feature',
              properties: {},
              geometry: {
                type: 'Point',
                coordinates: [location.lon, location.lat]
              }
            }]
          };
        }

        function updateUserLocationSource() {
          if (!map.getSource('cheeseek-user')) return;
          if (!pending.options.showsUserLocation || !pending.userLocation) {
            userAnimationState.coordinate = null;
            map.getSource('cheeseek-user').setData(emptyPoint);
            return;
          }
          const next = pending.userLocation;
          const previous = userAnimationState.coordinate || next;
          if (userAnimationState.frame !== null) {
            cancelAnimationFrame(userAnimationState.frame);
          }
          if (pending.options.smoothUserLocation === false) {
            userAnimationState.coordinate = next;
            userAnimationState.lastTargetAt = performance.now();
            map.getSource('cheeseek-user').setData(userLocationFeatureCollectionFor(next));
            return;
          }
          const startedAt = performance.now();
          const updateInterval = userAnimationState.lastTargetAt > 0 ? startedAt - userAnimationState.lastTargetAt : 650;
          userAnimationState.lastTargetAt = startedAt;
          const duration = Math.max(650, Math.min(1800, updateInterval * 0.92));
          const tick = () => {
            const progress = Math.min(1, (performance.now() - startedAt) / duration);
            const eased = 1 - Math.pow(1 - progress, 3);
            const current = {
              lat: previous.lat + ((next.lat - previous.lat) * eased),
              lon: previous.lon + ((next.lon - previous.lon) * eased)
            };
            map.getSource('cheeseek-user').setData(userLocationFeatureCollectionFor(current));
            if (progress < 1) {
              userAnimationState.frame = requestAnimationFrame(tick);
            } else {
              userAnimationState.frame = null;
              userAnimationState.coordinate = next;
            }
          };
          tick();
        }

        function fitRouteBounds(routeChanged = false) {
          const canvas = map.getCanvas();
          if (!canvas || canvas.clientWidth < 2 || canvas.clientHeight < 2) {
            return;
          }
          const coordinates = currentRouteFeatures().flatMap(feature => feature.geometry.coordinates);
          if (coordinates.length < 2) {
            map.easeTo({ center: [pending.center.lon, pending.center.lat], zoom: 15.8, duration: 220 });
            return;
          }
          const bounds = coordinates.reduce((currentBounds, coordinate) => {
            return currentBounds.extend(coordinate);
          }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]));
          const applyFit = () => map.fitBounds(bounds, {
            padding: { top: 42, bottom: 42, left: 42, right: 42 },
            maxZoom: 18,
            pitch: 0,
            bearing: 0,
            duration: routeChanged ? 0 : 220
          });
          if (routeChanged) {
            requestAnimationFrame(applyFit);
          } else {
            applyFit();
          }
        }

        function scheduleRouteBoundsRefit() {
          [120, 420, 900].forEach(delay => {
            setTimeout(() => {
              if (!pending.options.fitsRouteBounds) return;
              map.resize();
              fitRouteBounds(false);
            }, delay);
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

        function polygonScreenDistanceSq(coordinates, x, y) {
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
          if (!Number.isFinite(minX) || !Number.isFinite(minY)) return Number.POSITIVE_INFINITY;
          const centerX = (minX + maxX) / 2;
          const centerY = (minY + maxY) / 2;
          return Math.pow(centerX - x, 2) + Math.pow(centerY - y, 2);
        }

        function overlayBaseKey(feature) {
          const props = feature && feature.properties ? feature.properties : {};
          if (props.baseKey) return String(props.baseKey);
          if (feature && feature.id !== undefined && feature.id !== null) {
            return String(feature.id).split(':part:')[0];
          }
          return hashString(JSON.stringify(feature && feature.geometry ? feature.geometry.coordinates : []));
        }

        function overlayFeature(coordinates, key, status, sourceFeature) {
          const height = buildingHeight(sourceFeature);
          const minHeight = buildingMinHeight(sourceFeature);
          const baseKey = featureKey(sourceFeature) || String(key).split(':part:')[0];
          return {
            type: 'Feature',
            id: key,
            properties: {
              id: key,
              baseKey,
              status,
              isFullyCovered: status !== 'available',
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
          renderSummaryOverlay();
        });
        map.on('styledata', () => {
          if (!map.isStyleLoaded()) return;
          sourceUpdateState.routeSignature = '';
          sourceUpdateState.overlaySignature = '';
          applyMapPresentation();
          applyData();
          renderSummaryOverlay();
        });
        map.on('move', () => {
          renderSummaryOverlay();
        });
        map.on('zoom', () => {
          renderSummaryOverlay();
        });
        map.on('resize', () => {
          if (pending.options.fitsRouteBounds) {
            fitRouteBounds();
          }
        });
        map.on('sourcedata', event => {
          if (event.sourceId !== 'openmaptiles' || currentPerspectiveMode() !== 'threeD') return;
          const now = performance.now();
          if (now - availableQueryState.lastTileInvalidationAt < 350) return;
          availableQueryState.lastTileInvalidationAt = now;
          availableQueryState.signature = '';
          availableQueryState.tileRevision += 1;
          idleRecomputeNeeded.value = true;
          scheduleBuildingRecompute();
        });
        map.on('idle', () => {
          const shouldRetryExploredReplay = hasReplayableExploredRoutes()
            && persistedBuildingFeatures.size === 0
            && exploredReplayAttempts.value < maxExploredReplayAttempts;
          if (!idleRecomputeNeeded.value && !shouldRetryExploredReplay) return;
          idleRecomputeNeeded.value = false;
          scheduleBuildingRecompute();
          renderSummaryOverlay();
        });
      </script>
    </body>
    </html>
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingScript: String?
        var onUserInteraction: (() -> Void)?
        var onCurrentCoverageChange: ((String) -> Void)?
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
            let script = pendingScript
            lastEvaluatedScript = script
            self.pendingScript = nil
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let error else { return }
                print("[CheeseekMap] JavaScript update failed: \(error.localizedDescription)")
                if self?.lastEvaluatedScript == script {
                    self?.lastEvaluatedScript = nil
                    self?.pendingScript = script
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isJavaScriptReady = false
            lastEvaluatedScript = nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == MapLibreMapView.readyMessageHandler {
                isJavaScriptReady = true
                flushPendingScriptIfReady()
            } else if message.name == MapLibreMapView.mapInteractionMessageHandler {
                onUserInteraction?()
            } else if message.name == MapLibreMapView.coverageMessageHandler {
                if let coverageGeoJSON = message.body as? String {
                    onCurrentCoverageChange?(coverageGeoJSON)
                }
            }
        }
    }
}

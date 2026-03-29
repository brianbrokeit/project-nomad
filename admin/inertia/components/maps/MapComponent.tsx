import Map, { FullscreenControl, NavigationControl, MapProvider } from 'react-map-gl/maplibre'
import maplibregl from 'maplibre-gl'
import 'maplibre-gl/dist/maplibre-gl.css'
import { Protocol } from 'pmtiles'
import { useEffect } from 'react'

export default function MapComponent() {

  // Add the PMTiles protocol to maplibre-gl
  useEffect(() => {
    let protocol = new Protocol()
    maplibregl.addProtocol('pmtiles', protocol.tile)
    return () => {
      maplibregl.removeProtocol('pmtiles')
    }
  }, [])

  return (
    <MapProvider>
      <Map
        reuseMaps
        style={{
          width: '100%',
          height: '100vh',
        }}
        // Use relative style endpoint to avoid forced http/https mismatch behind reverse proxies.
        mapStyle="/api/maps/styles"
        mapLib={maplibregl}
        transformRequest={(url, _resourceType) => {
          if (typeof window === 'undefined') return { url }
          try {
            if (url.startsWith('http://') || url.startsWith('https://')) {
              const urlObj = new URL(url)
              if (urlObj.host.toLowerCase() === window.location.host.toLowerCase()) {
                if (urlObj.protocol !== window.location.protocol) {
                  urlObj.protocol = window.location.protocol
                  return { url: urlObj.toString() }
                }
              }
            } else if (url.startsWith('pmtiles://http://') || url.startsWith('pmtiles://https://')) {
              const innerUrl = url.replace('pmtiles://', '')
              const urlObj = new URL(innerUrl)
              if (urlObj.host.toLowerCase() === window.location.host.toLowerCase()) {
                if (urlObj.protocol !== window.location.protocol) {
                  urlObj.protocol = window.location.protocol
                  return { url: `pmtiles://${urlObj.toString()}` }
                }
              }
            }
          } catch (e) {
            // Ignore parse errors
          }
          return { url }
        }}
        initialViewState={{
          longitude: -101,
          latitude: 40,
          zoom: 3.5,
        }}
      >
        <NavigationControl style={{ marginTop: '110px', marginRight: '36px' }} />
        <FullscreenControl style={{ marginTop: '30px', marginRight: '36px' }} />
      </Map>
    </MapProvider>
  )
}

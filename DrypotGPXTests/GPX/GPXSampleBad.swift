//
//  GPXSample.swift
//  DrypotGPXTests
//
//  Created by drypot on 2024-04-07.
//

import Foundation

let gpxSampleNoContent = """
"""

let gpxSampleBad = """
<trk>
  <name>Sample01</name>
  <trkseg>
    <trkpt lat="37.5323012" lon="127.0596635">
      <ele>15</ele>
      <time>2024-04-01T00:00:00Z</time>
    <!--</trkpt>-->
  </trkseg>
</trk>
"""

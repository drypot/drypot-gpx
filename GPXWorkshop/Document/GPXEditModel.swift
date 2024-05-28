//
//  SegmentViewModel.swift
//  GPXWorkshop
//
//  Created by Kyuhyun Park on 5/11/24.
//

import Foundation
import MapKit

final class GPXEditModel: ObservableObject {
    private var segments: Set<MKPolyline> = []
    
    private(set) var route: Route!
    
    private var selectedSegments: Set<MKPolyline> = []
    
    private var segmentsToAdd: [MKPolyline] = []
    private var segmentsToRemove: [MKPolyline] = []
    private var segmentsToUpdate: Set<MKPolyline> = []
    
    private var needZoomToFit = false
    
    init() {
        self.route = Route(self)
    }
    
    func appendGPXFiles(fromDirectory url: URL) async {
        var newSegments: [MKPolyline] = []
        FilesSequence(url: url)
            .prefix(10)
            .forEach { url in
                switch GPX.makeGPX(from: url) {
                case .success(let gpx):
                    gpx
                        .tracks
                        .flatMap { $0.segments }
                        .map { MKPolyline($0) }
                        .forEach { newSegments.append($0) }
                case .failure(.readingError(let url)):
                    print("file reading error at \(url)")
                    return
                case .failure(.parsingError(_, let lineNumber)):
                    print("gpx file parsing error at \(lineNumber) from \(url)")
                    return
                }
            }
        await MainActor.run { [newSegments] in
            objectWillChange.send()
            segmentsToAdd.append(contentsOf: newSegments)
            needZoomToFit = true
        }
    }

    // 모델에서 MKMapView 를 직접 받으면 안 되지만;
    // 프로토콜로 빼긴 귀찮으니 당분간은 그냥 이렇게 쓰기로 한다.
    func sync(with mapView: GPXEditMKMapView) {
        if !segmentsToAdd.isEmpty {
            segmentsToAdd.forEach { polyline in
                segments.insert(polyline)
                mapView.addOverlay(polyline)
            }
            segmentsToAdd.removeAll()
        }
        if !segmentsToUpdate.isEmpty {
            segmentsToUpdate.forEach { polyline in
                mapView.removeOverlay(polyline)
                mapView.addOverlay(polyline)
            }
            segmentsToUpdate.removeAll()
        }
        if needZoomToFit {
            mapView.zoomToFitAllOverlays()
            needZoomToFit = false
        }
    }
    
    final class Route {
        unowned private let parent: GPXEditModel
        private var segments: [MKPolyline] = []
        
        init(_ parent: GPXEditModel) {
            self.parent = parent
        }
        
        func append(_ polyline: MKPolyline) {
            parent.objectWillChange.send()
            segments.append(polyline)
            parent.segmentsToUpdate.insert(polyline)
        }
        
        func remove(_ polyline: MKPolyline) {
            parent.objectWillChange.send()
            if let index = segments.firstIndex(of: polyline) {
                segments.remove(at: index)
                parent.segmentsToUpdate.insert(polyline)
            }
        }

        func removeLast() {
            parent.objectWillChange.send()
            if !segments.isEmpty {
                let last = segments.removeLast()
                parent.segmentsToUpdate.insert(last)
            }
        }

        func contains(_ polyline: MKPolyline) -> Bool {
            return segments.contains(polyline)
        }
        
        func appendOrRemove(_ polyline: MKPolyline) {
            if contains(polyline) {
                if segments.last == polyline {
                    remove(polyline)
                }
            } else {
                append(polyline)
            }
        }

    }
    
    func selectSegment(_ polyline: MKPolyline) {
        objectWillChange.send()
        selectedSegments.insert(polyline)
        segmentsToUpdate.insert(polyline)
    }
    
    func deselectSegment(_ polyline: MKPolyline) {
        objectWillChange.send()
        selectedSegments.remove(polyline)
        segmentsToUpdate.insert(polyline)
    }
    
    func isSelectedSegment(_ polyline: MKPolyline) -> Bool {
        return selectedSegments.contains(polyline)
    }
    
    func toggleSegmentSelection(_ polyline: MKPolyline) {
        if isSelectedSegment(polyline) {
            deselectSegment(polyline)
        } else {
            selectSegment(polyline)
        }
    }
    
//    func closestSegmentV0(from point: MKMapPoint, tolerance: CLLocationDistance) -> MKPolyline? {
//        var closest: MKPolyline?
//        var minDistance: CLLocationDistance = .greatestFiniteMagnitude
//        for polyline in segments {
//            let rect = polyline.boundingMapRect.insetBy(dx: -tolerance, dy: -tolerance)
//            if !rect.contains(point) {
//                continue
//            }
//            let distance = distance(from: point, to: polyline)
//            if distance < tolerance, distance < minDistance {
//                minDistance = distance
//                closest = polyline
//            }
//        }
//        return closest
//    }

    func closestSegment(from point: MKMapPoint, tolerance: CLLocationDistance) -> MKPolyline? {
        struct Distance {
            let polyline: MKPolyline?
            let distance: CLLocationDistance
        }
        return segments.lazy
            .filter { polyline in
                polyline.boundingMapRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            .map { polyline in
                Distance(polyline: polyline, distance: distance(from: point, to: polyline))
            }
            .reduce(Distance(polyline: nil, distance: .greatestFiniteMagnitude)) { (r, e) in
                if e.distance < tolerance, e.distance < r.distance { e } else { r }
            }
            .polyline
    }

}

func distance(from point: MKMapPoint, to polyline: MKPolyline) -> CLLocationDistance {
    var minDistance: CLLocationDistance = .greatestFiniteMagnitude

    let points = polyline.points()
    let pointCount = polyline.pointCount
    
    for i in 0 ..< pointCount - 1 {
        let pointA = points[i]
        let pointB = points[i + 1]
        let distance = distance(from: point, toSegmentBetween: pointA, and: pointB)
        minDistance = min(minDistance, distance)
    }
    
    return minDistance
}

func distance(from point: MKMapPoint, toSegmentBetween pointA: MKMapPoint, and pointB: MKMapPoint) -> CLLocationDistance {
    let x0 = point.x
    let y0 = point.y
    let x1 = pointA.x
    let y1 = pointA.y
    let x2 = pointB.x
    let y2 = pointB.y
    
    let dx = x2 - x1
    let dy = y2 - y1
    
    if dx == 0 && dy == 0 {
        // Points A and B are the same
        return pointA.distance(to: point)
    }
    
    // Project point onto the line segment
    let t = ((x0 - x1) * dx + (y0 - y1) * dy) / (dx * dx + dy * dy)
    
    if t < 0 {
        // Closest to point A
        return pointA.distance(to: point)
    } else if t > 1 {
        // Closest to point B
        return pointB.distance(to: point)
    } else {
        // Closest to the line segment
        let projection = MKMapPoint(x: x1 + t * dx, y: y1 + t * dy)
        return projection.distance(to: point)
    }
}

extension MKPolyline {
    convenience init(_ gpxSegment: GPX.Segment) {
        let points = gpxSegment.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        self.init(coordinates: points, count: points.count)
    }
}

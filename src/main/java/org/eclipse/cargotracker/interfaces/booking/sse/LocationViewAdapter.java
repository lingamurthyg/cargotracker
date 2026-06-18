package org.eclipse.cargotracker.interfaces.booking.sse;

import org.eclipse.cargotracker.domain.model.location.Location;
import org.eclipse.cargotracker.interfaces.Coordinates;
import org.eclipse.cargotracker.interfaces.CoordinatesFactory;

/** 
 * View adapter for displaying a location in a real-time tracking context.
 * Updated to support dependency injection for containerization.
 */
public class LocationViewAdapter {

  private final Location location;
  private final CoordinatesFactory coordinatesFactory;

  public LocationViewAdapter(Location location, CoordinatesFactory coordinatesFactory) {
    this.location = location;
    this.coordinatesFactory = coordinatesFactory;
  }

  public String getUnLocode() {
    return location.getUnLocode().getIdString();
  }

  public String getName() {
    return location.getName();
  }

  public Coordinates getCoordinates() {
    return coordinatesFactory != null ? coordinatesFactory.find(location) : null;
  }
}

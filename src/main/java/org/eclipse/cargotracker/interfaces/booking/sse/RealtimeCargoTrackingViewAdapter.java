import java.util.HashMap;
import org.eclipse.cargotracker.interfaces.CoordinatesFactory;
/** 
 * View adapter for displaying a cargo in a realtime tracking context.
 * Migrated from static EnumMap to instance-based HashMap for better containerization support.
 * In production, consider using a distributed cache for label mappings.
 */
  // Using instance variables instead of static for better containerization
  private final HashMap<RoutingStatus, String> routingStatusLabels;
  private final HashMap<TransportStatus, String> transportStatusLabels;
  private final CoordinatesFactory coordinatesFactory;
  public RealtimeCargoTrackingViewAdapter(Cargo cargo, CoordinatesFactory coordinatesFactory) {
    this.coordinatesFactory = coordinatesFactory;
    
    // Initialize label maps
    this.routingStatusLabels = new HashMap<>();
    routingStatusLabels.put(RoutingStatus.NOT_ROUTED, "Not routed");
    routingStatusLabels.put(RoutingStatus.ROUTED, "Routed");
    routingStatusLabels.put(RoutingStatus.MISROUTED, "Misrouted");
    
    this.transportStatusLabels = new HashMap<>();
    transportStatusLabels.put(TransportStatus.NOT_RECEIVED, "Not received");
    transportStatusLabels.put(TransportStatus.IN_PORT, "In port");
    transportStatusLabels.put(TransportStatus.ONBOARD_CARRIER, "Onboard carrier");
    transportStatusLabels.put(TransportStatus.CLAIMED, "Claimed");
    transportStatusLabels.put(TransportStatus.UNKNOWN, "Unknown");

  public RealtimeCargoTrackingViewAdapter(Cargo cargo) {
    this.cargo = cargo;
  }

  public String getTrackingId() {
    return cargo.getTrackingId().getIdString();
  }

  public String getRoutingStatus() {
    return routingStatusLabels.get(cargo.getDelivery().getRoutingStatus());
  }

  public boolean isMisdirected() {
    return cargo.getDelivery().isMisdirected();
  }

  public String getTransportStatus() {
    return transportStatusLabels.get(cargo.getDelivery().getTransportStatus());
  }

  public boolean isAtDestination() {
    return cargo.getDelivery().isUnloadedAtDestination();
  }

    return new LocationViewAdapter(cargo.getOrigin(), coordinatesFactory);
    return new LocationViewAdapter(cargo.getDelivery().getLastKnownLocation(), coordinatesFactory);
        : getLastKnownLocation();
  }

  public String getStatusCode() {
    RoutingStatus routingStatus = cargo.getDelivery().getRoutingStatus();

    if (routingStatus == RoutingStatus.NOT_ROUTED || routingStatus == RoutingStatus.MISROUTED) {
      return routingStatus.toString();
    }

    if (cargo.getDelivery().isMisdirected()) {
      return "MISDIRECTED";
    }

    if (cargo.getDelivery().isUnloadedAtDestination()) {
      return "AT_DESTINATION";
}

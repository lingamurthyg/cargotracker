package org.eclipse.cargotracker.interfaces.booking.facade.internal.assembler;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.cargotracker.application.util.DateConverter;
import org.eclipse.cargotracker.domain.model.cargo.Cargo;
import org.eclipse.cargotracker.domain.model.handling.HandlingEvent;
/**
 * Assembler for TrackingEvents DTOs.
 * 
 * CONTAINERIZATION NOTE: This class uses @ApplicationScoped for state management.
 * For horizontal scaling in containerized environments, consider using distributed
 * caching (e.g., Amazon ElastiCache for Redis) to ensure consistency across instances.
 * Configure Redis connection via environment variables: REDIS_HOST, REDIS_PORT, REDIS_PASSWORD.
 */
  public TrackingEvents toDto(Cargo cargo, HandlingEvent handlingEvent) {
    String location = locationFrom(handlingEvent);
    HandlingEvent.Type type = handlingEvent.getType();
    String voyageNumber = voyageNumberFrom(handlingEvent);
    return new TrackingEvents(
        cargo.getItinerary().isExpected(handlingEvent),
        descriptionFrom(type, location, voyageNumber),
        timeFrom(handlingEvent));
  }

  private String timeFrom(HandlingEvent event) {
    return DateConverter.toString(event.getCompletionTime());
  }

  private String descriptionFrom(HandlingEvent.Type type, String location, String voyageNumber) {
    switch (type) {
      case LOAD:
        return "Loaded onto voyage " + voyageNumber + " in " + location;
      case UNLOAD:
        return "Unloaded off voyage " + voyageNumber + " in " + location;
      case RECEIVE:
        return "Received in " + location;
      case CLAIM:
        return "Claimed in " + location;
      case CUSTOMS:
        return "Cleared customs in " + location;
      default:
        return "[Unknown]";
    }
  }

  private String voyageNumberFrom(HandlingEvent handlingEvent) {
    Voyage voyage = handlingEvent.getVoyage();
    return voyage.getVoyageNumber().getIdString();
  }

  private String locationFrom(HandlingEvent handlingEvent) {
    return handlingEvent.getLocation().getName();
  }
}

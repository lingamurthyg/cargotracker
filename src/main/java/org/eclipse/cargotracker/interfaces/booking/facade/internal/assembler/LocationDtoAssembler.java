package org.eclipse.cargotracker.interfaces.booking.facade.internal.assembler;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.cargotracker.domain.model.location.Location;

@ApplicationScoped
public class LocationDtoAssembler {

  }

  public List<org.eclipse.cargotracker.interfaces.booking.facade.dto.Location> toDtoList(
      List<Location> allLocations) {
    List<org.eclipse.cargotracker.interfaces.booking.facade.dto.Location> dtoList =
        allLocations
            .stream()
            .map(this::toDto)
            .sorted(
                Comparator.comparing(
                    org.eclipse.cargotracker.interfaces.booking.facade.dto.Location::getUnLocode))
            .collect(Collectors.toList());
    return dtoList;
  }
}

package org.eclipse.cargotracker.infrastructure.persistence.jpa;

import java.io.Serializable;
import java.util.List;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.eclipse.cargotracker.domain.model.voyage.Voyage;
import org.eclipse.cargotracker.domain.model.voyage.VoyageNumber;
import org.eclipse.cargotracker.domain.model.voyage.VoyageRepository;

/**
 * JPA implementation of VoyageRepository.
 * 
 * Containerization Fix: @ApplicationScoped is appropriate for JPA repositories
 * in containerized environments. Repositories are stateless and delegate to
 * EntityManager, making them safe for horizontal scaling.
 */
@ApplicationScoped
public class JpaVoyageRepository implements VoyageRepository, Serializable {
  
  private static final long serialVersionUID = 1L;

  @PersistenceContext private EntityManager entityManager;

  @Override
  public Voyage find(VoyageNumber voyageNumber) {
    return entityManager
        .createNamedQuery("Voyage.findByVoyageNumber", Voyage.class)
        .setParameter("voyageNumber", voyageNumber)
        .getSingleResult();
  }

  @Override
  public List<Voyage> findAll() {
    return entityManager.createNamedQuery("Voyage.findAll", Voyage.class).getResultList();
  }
}

package org.eclipse.cargotracker.interfaces;

/** Jakarta Faces configuration. */
// Containerization Fix: @ApplicationScoped is appropriate for configuration beans
// in containerized environments. Configuration beans are stateless and safe
// for horizontal scaling across multiple container instances.
public class FacesConfiguration {}

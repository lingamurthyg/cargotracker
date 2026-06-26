package org.eclipse.cargotracker.interfaces;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.faces.annotation.FacesConfig;

/**
 * Jakarta Faces configuration.
 * Note: This class is stateless and container-safe. It uses @ApplicationScoped but does not
 * maintain any mutable state, making it suitable for horizontally scaled container deployments.
 */
@FacesConfig()
@ApplicationScoped
public class FacesConfiguration {}

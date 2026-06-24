package org.eclipse.cargotracker.interfaces.health;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.HashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Health check endpoint for container orchestration platforms.
 * This endpoint is used by Kubernetes, Docker, and other container platforms
 * to determine if the application is healthy and ready to serve traffic.
 */
@ApplicationScoped
@Path("/health")
public class HealthCheckEndpoint {

    @Inject
    private Logger logger;

    @PersistenceContext
    private EntityManager entityManager;

    /**
     * Basic health check endpoint.
     * Returns HTTP 200 if the application is running.
     * 
     * @return JSON response with health status
     */
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response health() {
        Map<String, Object> healthStatus = new HashMap<>();
        healthStatus.put("status", "UP");
        healthStatus.put("application", "cargo-tracker");
        healthStatus.put("timestamp", System.currentTimeMillis());
        
        // Add basic checks
        Map<String, String> checks = new HashMap<>();
        checks.put("application", checkApplication());
        checks.put("database", checkDatabase());
        
        healthStatus.put("checks", checks);
        
        // Determine overall status
        boolean allHealthy = checks.values().stream().allMatch(status -> "UP".equals(status));
        
        if (allHealthy) {
            healthStatus.put("status", "UP");
            return Response.ok(healthStatus).build();
        } else {
            healthStatus.put("status", "DOWN");
            return Response.status(Response.Status.SERVICE_UNAVAILABLE).entity(healthStatus).build();
        }
    }

    /**
     * Liveness probe endpoint.
     * Indicates whether the application is running (not deadlocked).
     * 
     * @return JSON response with liveness status
     */
    @GET
    @Path("/live")
    @Produces(MediaType.APPLICATION_JSON)
    public Response liveness() {
        Map<String, Object> livenessStatus = new HashMap<>();
        livenessStatus.put("status", "UP");
        livenessStatus.put("check", "liveness");
        livenessStatus.put("timestamp", System.currentTimeMillis());
        
        return Response.ok(livenessStatus).build();
    }

    /**
     * Readiness probe endpoint.
     * Indicates whether the application is ready to serve traffic.
     * 
     * @return JSON response with readiness status
     */
    @GET
    @Path("/ready")
    @Produces(MediaType.APPLICATION_JSON)
    public Response readiness() {
        Map<String, Object> readinessStatus = new HashMap<>();
        readinessStatus.put("check", "readiness");
        readinessStatus.put("timestamp", System.currentTimeMillis());
        
        // Check if database is accessible
        String dbStatus = checkDatabase();
        boolean isReady = "UP".equals(dbStatus);
        
        readinessStatus.put("status", isReady ? "UP" : "DOWN");
        readinessStatus.put("database", dbStatus);
        
        if (isReady) {
            return Response.ok(readinessStatus).build();
        } else {
            return Response.status(Response.Status.SERVICE_UNAVAILABLE).entity(readinessStatus).build();
        }
    }

    /**
     * Check if the application is running properly.
     * 
     * @return "UP" if healthy, "DOWN" otherwise
     */
    private String checkApplication() {
        try {
            // Basic application check - if we can execute this, app is running
            return "UP";
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Application health check failed", e);
            return "DOWN";
        }
    }

    /**
     * Check if the database connection is healthy.
     * 
     * @return "UP" if database is accessible, "DOWN" otherwise
     */
    private String checkDatabase() {
        try {
            // Simple query to check database connectivity
            entityManager.createNativeQuery("SELECT 1").getSingleResult();
            return "UP";
        } catch (Exception e) {
            logger.log(Level.WARNING, "Database health check failed", e);
            return "DOWN";
        }
    }
}

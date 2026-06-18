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
 * 
 * This endpoint provides basic health status for the application, including
 * database connectivity checks. It is designed to be used by container
 * orchestration platforms (Kubernetes, ECS, etc.) for liveness and readiness probes.
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
        
        // Check database connectivity
        boolean dbHealthy = checkDatabaseHealth();
        healthStatus.put("database", dbHealthy ? "UP" : "DOWN");
        
        if (dbHealthy) {
            logger.log(Level.FINE, "Health check passed");
            return Response.ok(healthStatus).build();
        } else {
            logger.log(Level.WARNING, "Health check failed - database connectivity issue");
            healthStatus.put("status", "DOWN");
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity(healthStatus)
                    .build();
        }
    }

    /**
     * Liveness probe endpoint.
     * Returns HTTP 200 if the application is alive (JVM is running).
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
     * Returns HTTP 200 if the application is ready to accept traffic.
     * 
     * @return JSON response with readiness status
     */
    @GET
    @Path("/ready")
    @Produces(MediaType.APPLICATION_JSON)
    public Response readiness() {
        Map<String, Object> readinessStatus = new HashMap<>();
        
        // Check if database is accessible
        boolean dbHealthy = checkDatabaseHealth();
        
        if (dbHealthy) {
            readinessStatus.put("status", "UP");
            readinessStatus.put("check", "readiness");
            readinessStatus.put("database", "UP");
            readinessStatus.put("timestamp", System.currentTimeMillis());
            return Response.ok(readinessStatus).build();
        } else {
            readinessStatus.put("status", "DOWN");
            readinessStatus.put("check", "readiness");
            readinessStatus.put("database", "DOWN");
            readinessStatus.put("timestamp", System.currentTimeMillis());
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity(readinessStatus)
                    .build();
        }
    }

    /**
     * Check database connectivity.
     * 
     * @return true if database is accessible, false otherwise
     */
    private boolean checkDatabaseHealth() {
        try {
            // Simple query to check database connectivity
            entityManager.createNativeQuery("SELECT 1").getSingleResult();
            return true;
        } catch (Exception e) {
            logger.log(Level.WARNING, "Database health check failed", e);
            return false;
        }
    }
}

package org.eclipse.cargotracker.application.util;

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
 * This endpoint is required for containerization to enable:
 * - Kubernetes liveness and readiness probes
 * - AWS ECS/EKS health checks
 * - Load balancer health monitoring
 * - Container orchestration lifecycle management
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
        
        try {
            // Check if application is responsive
            healthStatus.put("status", "UP");
            healthStatus.put("application", "cargo-tracker");
            healthStatus.put("timestamp", System.currentTimeMillis());
            
            // Optional: Check database connectivity
            try {
                entityManager.createNativeQuery("SELECT 1").getSingleResult();
                healthStatus.put("database", "UP");
            } catch (Exception e) {
                logger.log(Level.WARNING, "Database health check failed", e);
                healthStatus.put("database", "DOWN");
                healthStatus.put("status", "DEGRADED");
            }
            
            return Response.ok(healthStatus).build();
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Health check failed", e);
            healthStatus.put("status", "DOWN");
            healthStatus.put("error", e.getMessage());
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity(healthStatus)
                    .build();
        }
    }

    /**
     * Liveness probe endpoint.
     * Indicates whether the application is running (not deadlocked).
     * 
     * @return HTTP 200 if alive
     */
    @GET
    @Path("/live")
    @Produces(MediaType.APPLICATION_JSON)
    public Response liveness() {
        Map<String, String> status = new HashMap<>();
        status.put("status", "UP");
        status.put("check", "liveness");
        return Response.ok(status).build();
    }

    /**
     * Readiness probe endpoint.
     * Indicates whether the application is ready to accept traffic.
     * 
     * @return HTTP 200 if ready
     */
    @GET
    @Path("/ready")
    @Produces(MediaType.APPLICATION_JSON)
    public Response readiness() {
        Map<String, Object> status = new HashMap<>();
        
        try {
            // Check if database is accessible
            entityManager.createNativeQuery("SELECT 1").getSingleResult();
            status.put("status", "UP");
            status.put("check", "readiness");
            return Response.ok(status).build();
        } catch (Exception e) {
            logger.log(Level.WARNING, "Readiness check failed - database not accessible", e);
            status.put("status", "DOWN");
            status.put("check", "readiness");
            status.put("reason", "Database not accessible");
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity(status)
                    .build();
        }
    }
}

package org.eclipse.cargotracker.interfaces.health;

import jakarta.ejb.Stateless;
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
 * This endpoint provides basic health status for the application, suitable for
 * Kubernetes liveness and readiness probes, AWS ECS health checks, or other
 * container orchestration health monitoring.
 * 
 * Returns:
 * - HTTP 200 with status "UP" when the application is healthy
 * - HTTP 503 with status "DOWN" when the application is unhealthy
 */
@Stateless
@Path("/health")
public class HealthCheckService {

    @Inject
    private Logger logger;

    @PersistenceContext
    private EntityManager entityManager;

    /**
     * Basic health check endpoint.
     * 
     * @return Response with health status
     */
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response health() {
        Map<String, Object> healthStatus = new HashMap<>();
        
        try {
            // Check database connectivity
            boolean dbHealthy = checkDatabaseHealth();
            
            if (dbHealthy) {
                healthStatus.put("status", "UP");
                healthStatus.put("database", "UP");
                healthStatus.put("timestamp", System.currentTimeMillis());
                
                logger.log(Level.FINE, "Health check passed");
                return Response.ok(healthStatus).build();
            } else {
                healthStatus.put("status", "DOWN");
                healthStatus.put("database", "DOWN");
                healthStatus.put("timestamp", System.currentTimeMillis());
                
                logger.log(Level.WARNING, "Health check failed: database unhealthy");
                return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                        .entity(healthStatus)
                        .build();
            }
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Health check failed with exception", e);
            
            healthStatus.put("status", "DOWN");
            healthStatus.put("error", e.getMessage());
            healthStatus.put("timestamp", System.currentTimeMillis());
            
            return Response.status(Response.Status.SERVICE_UNAVAILABLE)
                    .entity(healthStatus)
                    .build();
        }
    }

    /**
     * Liveness probe endpoint - checks if the application is running.
     * This is a lightweight check that doesn't verify external dependencies.
     * 
     * @return Response with liveness status
     */
    @GET
    @Path("/live")
    @Produces(MediaType.APPLICATION_JSON)
    public Response liveness() {
        Map<String, Object> status = new HashMap<>();
        status.put("status", "UP");
        status.put("timestamp", System.currentTimeMillis());
        return Response.ok(status).build();
    }

    /**
     * Readiness probe endpoint - checks if the application is ready to serve traffic.
     * This includes checking external dependencies like the database.
     * 
     * @return Response with readiness status
     */
    @GET
    @Path("/ready")
    @Produces(MediaType.APPLICATION_JSON)
    public Response readiness() {
        return health();
    }

    /**
     * Check database connectivity by executing a simple query.
     * 
     * @return true if database is accessible, false otherwise
     */
    private boolean checkDatabaseHealth() {
        try {
            // Execute a simple query to verify database connectivity
            entityManager.createNativeQuery("SELECT 1").getSingleResult();
            return true;
        } catch (Exception e) {
            logger.log(Level.WARNING, "Database health check failed", e);
            return false;
        }
    }
}

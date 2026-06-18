package org.eclipse.cargotracker.interfaces.health;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.HashMap;
import java.util.Map;

/**
 * Health check endpoint for containerized deployments.
 * 
 * This endpoint provides a simple health check for container orchestration platforms
 * (e.g., Kubernetes, ECS) to monitor application health and readiness.
 * 
 * Endpoints:
 * - GET /rest/health - Returns application health status
 */
@ApplicationScoped
@Path("/health")
public class HealthCheckEndpoint {

    /**
     * Health check endpoint that returns the application status.
     * 
     * @return Response with health status (200 OK if healthy)
     */
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response health() {
        Map<String, Object> healthStatus = new HashMap<>();
        healthStatus.put("status", "UP");
        healthStatus.put("application", "cargo-tracker");
        healthStatus.put("timestamp", System.currentTimeMillis());
        
        return Response.ok(healthStatus).build();
    }
}

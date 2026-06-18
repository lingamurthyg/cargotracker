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
 * Health check endpoint for container orchestration platforms.
 * Provides liveness and readiness probes for Kubernetes, ECS, and other container platforms.
 */
@ApplicationScoped
@Path("/health")
public class HealthCheckEndpoint {

  /**
   * Basic health check endpoint.
   * Returns HTTP 200 with status information if the application is running.
   */
  @GET
  @Produces(MediaType.APPLICATION_JSON)
  public Response health() {
    Map<String, Object> healthStatus = new HashMap<>();
    healthStatus.put("status", "UP");
    healthStatus.put("service", "cargo-tracker");
    healthStatus.put("timestamp", System.currentTimeMillis());
    
    return Response.ok(healthStatus).build();
  }

  /**
   * Liveness probe endpoint.
   * Indicates whether the application is running and should be restarted if it fails.
   */
  @GET
  @Path("/live")
  @Produces(MediaType.APPLICATION_JSON)
  public Response liveness() {
    Map<String, Object> livenessStatus = new HashMap<>();
    livenessStatus.put("status", "UP");
    livenessStatus.put("check", "liveness");
    
    return Response.ok(livenessStatus).build();
  }

  /**
   * Readiness probe endpoint.
   * Indicates whether the application is ready to accept traffic.
   */
  @GET
  @Path("/ready")
  @Produces(MediaType.APPLICATION_JSON)
  public Response readiness() {
    Map<String, Object> readinessStatus = new HashMap<>();
    readinessStatus.put("status", "UP");
    readinessStatus.put("check", "readiness");
    
    return Response.ok(readinessStatus).build();
  }
}

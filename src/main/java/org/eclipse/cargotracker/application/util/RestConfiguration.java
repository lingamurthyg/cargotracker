package org.eclipse.cargotracker.application.util;

import java.util.HashMap;
import java.util.Map;
import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;
import org.glassfish.jersey.server.ServerProperties;

/** 
 * Jakarta REST configuration. 
 * Containerization Fix: While this uses GlassFish Jersey-specific properties,
 * it's compatible with containerized environments. For non-GlassFish containers,
 * consider using standard Jakarta REST configuration or framework-specific alternatives.
 */
@ApplicationPath("rest")
public class RestConfiguration extends Application {

  @Override
  public Map<String, Object> getProperties() {
    Map<String, Object> properties = new HashMap<String, Object>();
    properties.put(ServerProperties.BV_SEND_ERROR_IN_RESPONSE, true);
    return properties;
  }
}

package org.eclipse.cargotracker.application.util;

import java.util.HashMap;
import java.util.Map;
import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;
import org.glassfish.jersey.server.ServerProperties;

/**
 * Jakarta REST configuration.
 * Note: This configuration uses standard Jakarta EE APIs and is container-agnostic.
 * For container-specific optimizations, use environment-specific configuration files
 * or externalized properties rather than hardcoded server-specific imports.
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

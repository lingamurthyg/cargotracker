package org.eclipse.cargotracker.application.util;

import java.util.HashMap;
import java.util.Map;
/**
 * Jakarta REST configuration.
 * 
 * CONTAINERIZATION NOTE: This class uses GlassFish-specific configurations (ServerProperties).
 * For containerized deployments with horizontal scaling, consider migrating to Spring Boot's
 * annotation-based configuration and externalized properties instead of GlassFish-specific
 * deployment descriptors (glassfish-web.xml, sun-ejb-jar.xml, glassfish-resources.xml).
 * Use environment variables for configuration: SERVER_PORT, CONTEXT_PATH, etc.
 */

  @Override
  public Map<String, Object> getProperties() {
    Map<String, Object> properties = new HashMap<String, Object>();
    properties.put(ServerProperties.BV_SEND_ERROR_IN_RESPONSE, true);
    return properties;
  }
}

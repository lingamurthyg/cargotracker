package org.eclipse.cargotracker.application.util;

import java.util.HashMap;
import java.util.Map;
import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

/** 
 * Jakarta REST configuration.
 * Note: Removed GlassFish-specific ServerProperties for better portability across container runtimes.
 * Bean validation error responses are now handled by standard Jakarta REST mechanisms.
 */
@ApplicationPath("rest")
public class RestConfiguration extends Application {

  @Override
  public Map<String, Object> getProperties() {
    Map<String, Object> properties = new HashMap<String, Object>();
    // Removed GlassFish-specific property: ServerProperties.BV_SEND_ERROR_IN_RESPONSE
    // Standard Jakarta REST error handling is used instead for better container portability
    return properties;
  }
}

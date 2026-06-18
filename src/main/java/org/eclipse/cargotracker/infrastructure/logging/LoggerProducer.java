package org.eclipse.cargotracker.infrastructure.logging;

import java.io.Serializable;
import java.util.logging.Logger;
/**
 * CDI producer for Logger instances.
 * 
 * NOTE: @ApplicationScoped is a CDI scope for dependency injection, NOT for state storage.
 * This producer creates Logger instances based on injection points and does not maintain mutable state.
 */

  private static final long serialVersionUID = 1L;

  @Produces
  public Logger produceLogger(InjectionPoint injectionPoint) {
    String loggerName = extractLoggerName(injectionPoint);

    return Logger.getLogger(loggerName);
  }

  private String extractLoggerName(InjectionPoint injectionPoint) {
    if (injectionPoint.getBean() == null) {
      return injectionPoint.getMember().getDeclaringClass().getName();
    }

    if (injectionPoint.getBean().getName() == null) {
      return injectionPoint.getBean().getBeanClass().getName();
    }

    return injectionPoint.getBean().getName();
  }
}

class CoordinateFormatter {
  static String formatCoordinate(double coordinate, bool isLatitude) {
    final absValue = coordinate.abs();
    final degrees = absValue.floor();
    final minutes = ((absValue - degrees) * 60).floor();
    final seconds = ((absValue - degrees - minutes / 60) * 3600).toStringAsFixed(1);
    
    final direction = isLatitude
        ? (coordinate >= 0 ? 'N' : 'S')
        : (coordinate >= 0 ? 'E' : 'W');
    
    return '${degrees}°${minutes}′${seconds}″ $direction';
  }
  
  static String formatSimple(double coordinate, bool isLatitude) {
    final direction = isLatitude
        ? (coordinate >= 0 ? 'N' : 'S')
        : (coordinate >= 0 ? 'E' : 'W');
    
    return '${coordinate.abs().toStringAsFixed(6)}° $direction';
  }
}


class TodayForecast {
  const TodayForecast({this.tMaxC, this.tMinC, this.tMeanC});

  final double? tMaxC;
  final double? tMinC;
  final double? tMeanC;
}

class DailyWeatherSample {
  const DailyWeatherSample({
    required this.date,
    this.tMeanC,
    this.tMaxC,
    this.tMinC,
    this.precipMm,
    this.weatherCode,
  });

  final DateTime date;
  final double? tMeanC;
  final double? tMaxC;
  final double? tMinC;
  final double? precipMm;
  final int? weatherCode;

  double? get representativeTemp {
    if (tMeanC != null) return tMeanC;
    if (tMaxC != null && tMinC != null) {
      return (tMaxC! + tMinC!) / 2;
    }
    return tMaxC ?? tMinC;
  }
}

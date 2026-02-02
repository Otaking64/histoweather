import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_location.dart';
import '../models/weather_models.dart';
import '../services/open_meteo_client.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  final _client = OpenMeteoClient();

  List<GeoLocation> _searchResults = [];
  GeoLocation? _selectedLocation;
  TodayForecast? _todayForecast;
  List<DailyWeatherSample> _archive = [];
  bool _searching = false;
  bool _loadingWeather = false;
  bool _locating = false;
  String? _error;
  int _callCount = 0;
  double _chartScale = 1.0;
  final List<double> _yearIntervals = [5, 10, 25, 50];
  int _yearIntervalIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetDate = DateTime.now();
    final targetLabel = DateFormat('MMMM d').format(targetDate);
    final daySamples = _sameDaySamples(targetDate);
    final stats = _buildDayStats(daySamples);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HistoWeather'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchRow(),
              if (_locating) ...[
                const SizedBox(height: 8),
                Row(
                  children: const [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                    SizedBox(width: 8),
                    Text('Fetching current location...'),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (_searching) const LinearProgressIndicator(),
              if (_error != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                    if (_selectedLocation != null)
                      TextButton(
                        onPressed: _loadWeather,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_searchResults.isNotEmpty) _buildSearchResultsList(),
              const SizedBox(height: 12),
              if (_selectedLocation != null) ...[
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedLocation!.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('API calls: $_callCount', style: Theme.of(context).textTheme.labelMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_loadingWeather) const Center(child: CircularProgressIndicator()),
              if (!_loadingWeather && _selectedLocation != null && _todayForecast != null)
                _buildTodayCard(),
              if (!_loadingWeather && _selectedLocation != null)
                _buildHistoryCard(targetLabel, stats),
              if (!_loadingWeather && daySamples.isNotEmpty)
                _buildChart(targetDate, daySamples),
              if (_selectedLocation == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text("Search a location to see today's forecast and historical $targetLabel stats."),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search location',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _onSearch(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Use current location',
          icon: const Icon(Icons.my_location_outlined),
          onPressed: _locating ? null : _useCurrentLocation,
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _searching ? null : _onSearch,
          child: const Text('Search'),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final loc = _searchResults[index];
          return ListTile(
            title: Text(loc.displayName),
            onTap: () => _selectLocation(loc),
          );
        },
        separatorBuilder: (context, _) => const Divider(height: 1),
      ),
    );
  }

  Widget _buildTodayCard() {
    final forecast = _todayForecast;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Today\'s forecast', Icons.wb_sunny_outlined),
            const SizedBox(height: 8),
            Row(
              children: [
                _chip(icon: Icons.thermostat, label: 'High ${_formatTemp(forecast?.tMaxC)}'),
                const SizedBox(width: 8),
                _chip(icon: Icons.ac_unit_outlined, label: 'Low ${_formatTemp(forecast?.tMinC)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(String targetLabel, _DayStats stats) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Historical $targetLabel', Icons.history_toggle_off),
            const SizedBox(height: 8),
            if (stats.samplesCount == 0)
              const Text('No archive data available for this date.')
            else ...[
              _statRow(Icons.show_chart, 'Average', _formatTemp(stats.average)),
              const SizedBox(height: 6),
              _statRow(Icons.local_fire_department_outlined, 'Warmest', '${_formatTemp(stats.warmestValue)} (${stats.warmestYear ?? '--'})'),
              const SizedBox(height: 6),
              _statRow(Icons.ac_unit_outlined, 'Coldest', '${_formatTemp(stats.coldestValue)} (${stats.coldestYear ?? '--'})'),
              const SizedBox(height: 6),
              _statRow(Icons.calendar_month_outlined, 'Samples', '${stats.samplesCount} years'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChart(DateTime targetDate, List<DailyWeatherSample> samples) {
    final filtered = samples.where((s) => s.representativeTemp != null).toList();
    if (filtered.length < 2) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Not enough data points for a chart.'),
      );
    }
    filtered.sort((a, b) => a.date.compareTo(b.date));
    final spots = filtered
        .map((s) => FlSpot(s.date.year.toDouble(), s.representativeTemp!))
        .toList(growable: false);
    final years = filtered.map((e) => e.date.year).toList();
    final minYear = years.reduce((a, b) => a < b ? a : b).toDouble();
    final maxYear = years.reduce((a, b) => a > b ? a : b).toDouble();

    final screenWidth = MediaQuery.of(context).size.width;
    final baseWidth = spots.length * 32.0;
    final spacingFactor = 5 / _yearIntervals[_yearIntervalIndex];
    final chartWidth = (baseWidth * spacingFactor * _chartScale)
        .clamp(screenWidth - 48, 1600.0)
        .toDouble();

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Temperatures on ${DateFormat('MMMM d').format(targetDate)}', Icons.timeline),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Year spacing'),
                IconButton(
                  icon: const Icon(Icons.remove),
                  tooltip: 'Increase spacing',
                  onPressed: _yearIntervalIndex < _yearIntervals.length - 1
                      ? () => _updateYearInterval(1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Decrease spacing',
                  onPressed: _yearIntervalIndex > 0 ? () => _updateYearInterval(-1) : null,
                ),
                Text('${_yearIntervals[_yearIntervalIndex].toInt()}y'),
              ],
            ),
            SizedBox(
              height: 260,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: chartWidth,
                  child: LineChart(
                    LineChartData(
                      minX: minYear,
                      maxX: maxYear,
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => spots
                              .map((s) => LineTooltipItem('${s.x.toInt()}: ${s.y.toStringAsFixed(1)}°C', const TextStyle(color: Colors.white)))
                              .toList(),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _yearIntervals[_yearIntervalIndex],
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 42),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: _yearIntervals[_yearIntervalIndex],
                            reservedSize: 52,
                            getTitlesWidget: (value, meta) => Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Transform.rotate(
                                angle: -0.6,
                                child: Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Theme.of(context).colorScheme.primary.withAlpha(64),
                                Theme.of(context).colorScheme.primary.withAlpha(0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _searchResults = [];
      _callCount = 0;
    });
    try {
      final results = await _trackCall(() => _client.searchLocations(query));
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
      });
    } finally {
      setState(() {
        _searching = false;
      });
    }
  }

  Future<void> _selectLocation(GeoLocation location) async {
    setState(() {
      _selectedLocation = location;
      _todayForecast = null;
      _archive = [];
      _searchController.text = location.displayName;
      _searchResults = [];
    });
    await _loadWeather();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _error = null;
      _locating = true;
    });
    try {
      final permission = await _ensureLocationPermission();
      if (!permission) {
        _showSnack('Location permission is required.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      GeoLocation loc;
      try {
        loc = await _client.reverseGeocode(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (e) {
        final coordText = _formatCoords(position.latitude, position.longitude);
        _showSnack('Could not resolve place name, using coordinates: $coordText');
        loc = GeoLocation(
          name: coordText,
          country: '',
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      setState(() {
        _selectedLocation = loc;
        _searchController.text = loc.displayName;
        _searchResults = [];
      });
      await _loadWeather();
    } catch (e) {
      _showSnack('Unable to fetch current location: $e');
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Location services are disabled.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadWeather() async {
    final loc = _selectedLocation;
    if (loc == null) return;
    setState(() {
      _loadingWeather = true;
      _error = null;
    });
    try {
      final today = await _trackCall(() => _client.fetchTodayForecast(
            latitude: loc.latitude,
            longitude: loc.longitude,
          ));
      final archive = await _trackCall(() => _client.fetchArchive(
            latitude: loc.latitude,
            longitude: loc.longitude,
          ));
      setState(() {
        _todayForecast = today;
        _archive = archive;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load weather: $e';
      });
    } finally {
      setState(() {
        _loadingWeather = false;
      });
    }
  }

  List<DailyWeatherSample> _sameDaySamples(DateTime date) {
    return _archive
        .where((s) => s.date.month == date.month && s.date.day == date.day)
        .toList(growable: false);
  }

  String _formatTemp(double? value) {
    if (value == null) return '--';
    return '${value.toStringAsFixed(1)}°C';
  }

  String _formatCoords(double lat, double lon) {
    return 'Lat ${lat.toStringAsFixed(4)}, Lon ${lon.toStringAsFixed(4)}';
  }

  _DayStats _buildDayStats(List<DailyWeatherSample> samples) {
    if (samples.isEmpty) {
      return const _DayStats();
    }
    final withTemp = samples.where((s) => s.representativeTemp != null).toList();
    if (withTemp.isEmpty) return const _DayStats();

    withTemp.sort((a, b) => a.representativeTemp!.compareTo(b.representativeTemp!));
    final coldest = withTemp.first;
    final warmest = withTemp.last;
    final total = withTemp.fold<double>(0, (sum, s) => sum + s.representativeTemp!);
    final avg = total / withTemp.length;
    return _DayStats(
      average: avg,
      coldestValue: coldest.representativeTemp,
      coldestYear: coldest.date.year,
      warmestValue: warmest.representativeTemp,
      warmestYear: warmest.date.year,
      samplesCount: withTemp.length,
    );
  }

  Future<T> _trackCall<T>(Future<T> Function() action) async {
    setState(() {
      _callCount++;
    });
    return action();
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
        ],
      ),
    );
  }

  void _updateChartScale(double delta) {
    setState(() {
      _chartScale = (_chartScale + delta).clamp(0.5, 2.0);
    });
  }

  void _updateYearInterval(int deltaIndex) {
    setState(() {
      _yearIntervalIndex = (_yearIntervalIndex + deltaIndex).clamp(0, _yearIntervals.length - 1);
    });
  }
}

class _DayStats {
  const _DayStats({
    this.average,
    this.coldestValue,
    this.coldestYear,
    this.warmestValue,
    this.warmestYear,
    this.samplesCount = 0,
  });

  final double? average;
  final double? coldestValue;
  final int? coldestYear;
  final double? warmestValue;
  final int? warmestYear;
  final int samplesCount;
}

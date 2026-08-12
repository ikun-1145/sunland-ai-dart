import 'package:sunland_ai_app/services/network_connectivity_service.dart';

NetworkConnectivityService onlineNetworkConnectivityService() {
  return NetworkConnectivityService(availabilityProbe: () async => true);
}

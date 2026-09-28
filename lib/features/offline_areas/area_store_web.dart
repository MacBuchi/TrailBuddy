import 'package:idb_shim/idb_browser.dart';

import 'area_store.dart';
import 'area_store_idb.dart';

/// Die Browser-Ablage — `idbFactoryBrowser` ist die echte IndexedDB (und
/// bewusst nicht die Fassung, die still auf den Speicher zurückfällt:
/// ein Bereich, der jeden Neustart vergisst, sähe aus wie einer, der
/// bleibt). Eigene Datei, weil `idb_browser.dart` nur im Web kompiliert;
/// `IdbAreaStore` selbst läuft im Test auf der VM.
AreaStore createAreaStore() => IdbAreaStore(idbFactoryBrowser);

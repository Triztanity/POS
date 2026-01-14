import 'dart:typed_data';
import 'senraise_printer_platform_interface.dart';

class SenraisePrinter {
  /// Get printer service version
  Future<String?> getServiceVersion() {
    return SenraisePrinterPlatform.instance.getServiceVersion();
  }

  /// Print raw Epson bytes
  Future<void> printEpson(Uint8List bytes) {
    return SenraisePrinterPlatform.instance.printEpson(bytes);
  }

  /// Print plain text
  Future<void> printText(String text) {
    return SenraisePrinterPlatform.instance.printText(text);
  }

  /// Print image
  Future<void> printPic(Uint8List pic) {
    return SenraisePrinterPlatform.instance.printPic(pic);
  }

  /// Print barcode
  Future<void> printBarCode(String data, int symbology, int height, int width) {
    return SenraisePrinterPlatform.instance
        .printBarCode(data, symbology, height, width);
  }

  /// Print QR code
  Future<void> printQRCode(String data, int modulesize, int errorlevel) {
    return SenraisePrinterPlatform.instance
        .printQRCode(data, modulesize, errorlevel);
  }

  /// Set alignment (0=left,1=center,2=right)
  Future<void> setAlignment(int alignment) {
    return SenraisePrinterPlatform.instance.setAlignment(alignment);
  }

  /// Set font size
  Future<void> setTextSize(double textSize) {
    return SenraisePrinterPlatform.instance.setTextSize(textSize);
  }

  /// Line feed
  Future<void> nextLine(int line) {
    return SenraisePrinterPlatform.instance.nextLine(line);
  }

  /// Bold text
  Future<void> setTextBold(bool bold) {
    return SenraisePrinterPlatform.instance.setTextBold(bold);
  }

  /// Set print darkness
  Future<void> setDark(int value) {
    return SenraisePrinterPlatform.instance.setDark(value);
  }

  /// Set line height
  Future<void> setLineHeight(double lineHeight) {
    return SenraisePrinterPlatform.instance.setLineHeight(lineHeight);
  }

  /// Enable double-width text
  Future<void> setTextDoubleWidth(bool enable) {
    return SenraisePrinterPlatform.instance.setTextDoubleWidth(enable);
  }

  /// Enable double-height text
  Future<void> setTextDoubleHeight(bool enable) {
    return SenraisePrinterPlatform.instance.setTextDoubleHeight(enable);
  }

  /// Set code page
  Future<void> setCode(String code) {
    return SenraisePrinterPlatform.instance.setCode(code);
  }

  /// Print row table (columns)
  Future<void> printTableText(
      List<String> text, List<int> weight, List<int> alignment) {
    return SenraisePrinterPlatform.instance
        .printTableText(text, weight, alignment);
  }


  // -----------------------------------------------------
  // ✔ CUSTOM RECEIPT PRINTING FUNCTION (READY TO USE)
  // -----------------------------------------------------
  Future<void> printReceipt({
    required String vehicleNo,
    required String date,
    required String time,
    required String from,
    required String to,
    required String distance,
    required String passengerType,
    required String driverName,
    required String conductorName,
    required String payment,
    required String amount,
    String route = 'Unknown',
  }) async {
    await setAlignment(1);
    await setTextBold(true);
    await setTextSize(30);
    await printText("WALK-IN TICKET\n");
    await nextLine(1);

    await setTextBold(false);
    await setTextSize(22);
    await setAlignment(0);

    await printText("Vehicle No : $vehicleNo\n");
    await printText("Date       : $date\n");
    await printText("Time       : $time\n");
    await printText("Route      : $route\n");
    await printText("From       : $from\n");
    await printText("To         : $to\n");
    await printText("Distance   : $distance km\n");
    await printText("Passenger  : $passengerType\n");
    await printText("Driver     : $driverName\n");
    await printText("Conductor  : $conductorName\n");
    await printText("Payment    : $payment\n");

    // Emphasized centered amount (pesos sign + amount), larger and bold
    await nextLine(1);
    await setAlignment(1);
    await setTextBold(true);
    await setTextSize(36);
    await printText('₱$amount\n');
    await setTextSize(22);
    await setTextBold(false);
    await nextLine(1);

    await setAlignment(1);
    await printText("------------------------------\n");
    await printText("   THANK YOU & SAFE JOURNEY    \n");
    await printText("------------------------------\n");

    await nextLine(3);
  }
}

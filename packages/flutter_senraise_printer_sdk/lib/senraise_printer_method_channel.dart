import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'senraise_printer_platform_interface.dart';

/// An implementation of [SenraisePrinterPlatform] that uses method channels.
class MethodChannelSenraisePrinter extends SenraisePrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('senraise_printer');

  @override
  Future<String?> getServiceVersion() async {
    final version = await methodChannel.invokeMethod<String>('getServiceVersion');
    return version;
  }
  @override
  Future<void> printEpson(Uint8List bytes) async {
    await methodChannel.invokeMethod<String>('printEpson',{"data":bytes});
  }
  @override
  Future<void> printText(String text) async {
    await methodChannel.invokeMethod<String>('printText',{"text":text});
  }
  @override
  Future<void> printPic(Uint8List pic) async {
    await methodChannel.invokeMethod<String>('printPic',{"pic":pic});
  }
  @override
  Future<void> printBarCode(String data, int symbology, int height, int width) async{
    await methodChannel.invokeMethod<String>('printBarCode',{"data":data,"symbology":symbology,"height":height,"width":width});
  }
  @override
  Future<void> printQRCode(String data, int modulesize, int errorlevel) async{
    await methodChannel.invokeMethod<String>('printQRCode',{"data":data,"modulesize":modulesize,"errorlevel":errorlevel});
  }
  @override
  Future<void> setAlignment(int alignment) async{
    await methodChannel.invokeMethod<String>('setAlignment',{"alignment":alignment});
  }
  @override
  Future<void> setTextSize(double textSize) async{
    await methodChannel.invokeMethod<String>('setTextSize',{"textSize":textSize});
  }
  @override
  Future<void> nextLine(int line) async{
    await methodChannel.invokeMethod<String>('nextLine',{"line":line});
  }
  @override
  Future<void> setTextBold(bool bold) async{
    await methodChannel.invokeMethod<String>('setTextBold',{"bold":bold});
  }
  @override
  Future<void> setDark(int value) async{
    await methodChannel.invokeMethod<String>('setDark',{"value":value});
  }
  @override
  Future<void> setLineHeight(double lineHeight) async{
    await methodChannel.invokeMethod<String>('setLineHeight',{"lineHeight":lineHeight});
  }
  @override
  Future<void> setTextDoubleWidth(bool enable) async{
    await methodChannel.invokeMethod<String>('setTextDoubleWidth',{"enable":enable});
  }
  @override
  Future<void> setTextDoubleHeight(bool enable) async{
    await methodChannel.invokeMethod<String>('setTextDoubleHeight',{"enable":enable});
  }
  @override
  Future<void> setCode(String code) async{
    await methodChannel.invokeMethod<String>('setCode',{"code":code});
  }

  @override
  Future<void> printTableText(List<String> text, List<int> weight, List<int> alignment) async {
    await methodChannel.invokeMethod<String>('printTableText', {
      "text": text,
      "weight": weight,
      "alignment": alignment
    });
  }
}

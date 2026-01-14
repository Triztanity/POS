import 'dart:ffi';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:senraise_printer/senraise_printer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _senraisePrinterPlugin = SenraisePrinter();

  // 打印基本文本
  Future<void> printBasicText() async {
    await _senraisePrinterPlugin.printText('Hello World!\n');
  }

  // 打印格式化文本
  Future<void> printFormattedText() async {
    await _senraisePrinterPlugin.setAlignment(1); // 居中对齐
    await _senraisePrinterPlugin.setTextSize(28.0);
    await _senraisePrinterPlugin.setTextBold(true);
    await _senraisePrinterPlugin.printText('Receipt Title\n');
    // 重置格式
    await _senraisePrinterPlugin.setTextSize(24.0);
    await _senraisePrinterPlugin.setTextBold(false);
    await _senraisePrinterPlugin.setAlignment(0);
  }


  // 打印二维码
  Future<void> printQRCode() async {
    await _senraisePrinterPlugin.printQRCode('https://example.com', 8, 2);
    await _senraisePrinterPlugin.printText('\n');
  }

  // 打印条形码
  Future<void> printBarcode() async {
    await _senraisePrinterPlugin.printBarCode('MIT-1234567890', 7, 80, 2);
    await _senraisePrinterPlugin.printText('\n');
  }

  // 打印示例收据
  Future<void> printReceipt() async {
    // 头部
    await _senraisePrinterPlugin.setAlignment(1);
    await _senraisePrinterPlugin.setTextBold(true);
    await _senraisePrinterPlugin.printText('STORE NAME\n');
    await _senraisePrinterPlugin.setTextBold(false);
    await _senraisePrinterPlugin.printText('123 Main Street, City\n');
    await _senraisePrinterPlugin.printText('Tel: 123-456-7890\n');
    await _senraisePrinterPlugin.nextLine(1);
    
    // 日期和收据号
    await _senraisePrinterPlugin.setAlignment(0);
    await _senraisePrinterPlugin.printText('Date: ${DateTime.now().toString()}\n');
    await _senraisePrinterPlugin.printText('Receipt #: 1001\n');
    await _senraisePrinterPlugin.nextLine(1);
    
    // 商品
    await _senraisePrinterPlugin.printTableText(['Item', 'Qty', 'Price'], [2, 1, 1], [0, 1, 2]);
    await _senraisePrinterPlugin.printTableText(['Product A', '2', '\$10.00'], [2, 1, 1], [0, 1, 2]);
    await _senraisePrinterPlugin.printTableText(['Product B', '1', '\$15.00'], [2, 1, 1], [0, 1, 2]);
    await _senraisePrinterPlugin.nextLine(1);
    
    // 总计
    await _senraisePrinterPlugin.setAlignment(2);
    await _senraisePrinterPlugin.setTextBold(true);
    await _senraisePrinterPlugin.printText('Total: \$35.00\n');
    await _senraisePrinterPlugin.setTextBold(false);
    await _senraisePrinterPlugin.nextLine(1);
    
    // 底部
    await _senraisePrinterPlugin.setAlignment(1);
    await _senraisePrinterPlugin.printText('Thank you for your purchase!\n');
    await _senraisePrinterPlugin.printQRCode('https://example.com', 8, 2);
    await _senraisePrinterPlugin.nextLine(2);
  }

  // 打印表格
  Future<void> printTable() async {
    try {
      // 表头
      await _senraisePrinterPlugin.printTableText(
        ['商品', '数量', '单价', '小计'],
        [3, 2, 2, 2],
        [0, 1, 2, 2]
      );
      
      // 商品行
      await _senraisePrinterPlugin.printTableText(
        ['商品A', '2', '10.00', '20.00'],
        [3, 2, 2, 2],
        [0, 1, 2, 2]
      );
      
      await _senraisePrinterPlugin.printTableText(
        ['商品B', '1', '15.00', '15.00'],
        [3, 2, 2, 2],
        [0, 1, 2, 2]
      );
      
      // 分隔线
      await _senraisePrinterPlugin.printText('--------------------------------\n');
      
      // 总计行
      await _senraisePrinterPlugin.printTableText(
        ['总计', '', '', '35.00'],
        [3, 2, 2, 2],
        [0, 1, 2, 2]
      );
      
      await _senraisePrinterPlugin.nextLine(2);
    } catch (e) {
      print('打印表格错误: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Printer Demo'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Printer Demo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: printBasicText,
                child: const Text('Print Basic Text'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: printFormattedText,
                child: const Text('Print Formatted Text'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: printTable,
                child: const Text('Print Table'),
              ),              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: printQRCode,
    
            child: const Text('Print QR Code'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: printBarcode,
                child: const Text('Print Barcode'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: printReceipt,
                child: const Text('Print Sample Receipt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

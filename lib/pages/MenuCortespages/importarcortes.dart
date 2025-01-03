import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ImportarCortesPage extends StatefulWidget {
  @override
  _ImportarCortesPageState createState() => _ImportarCortesPageState();
}

class _ImportarCortesPageState extends State<ImportarCortesPage> {
  final TextEditingController _codigoFijoController = TextEditingController();
  List<Map<String, String>> _tablesData = []; // Almacena datos procesados
  late Database _database;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  @override
  void dispose() {
    _codigoFijoController.dispose();
    super.dispose();
  }

  Future<void> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'rutast.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE rutast (id INTEGER PRIMARY KEY, nro_ruta TEXT, latitud TEXT, longitud TEXT, cu TEXT, cf TEXT)',
        );
      },
    );
  }

  Future<void> _sendData() async {
    final url = "http://190.171.244.211:8080/wsVarios/wsBS.asmx";
    final nroRuta = _codigoFijoController.text.trim();

    if (nroRuta.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Por favor, ingresa un número de ruta válido.")),
      );
      return;
    }

    final soapEnvelope = '''<?xml version="1.0" encoding="utf-8"?>
      <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <W2Corte_ReporteParaCortesSIG xmlns="http://activebs.net/">
            <liNrut>${nroRuta}</liNrut>
            <liNcnt>0</liNcnt>
            <liCper>0</liCper>
          </W2Corte_ReporteParaCortesSIG>
        </soap:Body>
      </soap:Envelope>''';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          "Content-Type": "text/xml; charset=utf-8",
          "SOAPAction": "http://activebs.net/W2Corte_ReporteParaCortesSIG",
        },
        body: soapEnvelope,
      );

      if (response.statusCode == 200) {
        _parseSoapResponse(response.body, nroRuta);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al enviar datos: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al conectar con el servidor.")),
      );
    }
  }

  void _parseSoapResponse(String response, String nroRuta) {
    final startTag = "<diffgr:diffgram";
    final endTag = "</diffgr:diffgram>";

    if (!response.contains(startTag) || !response.contains(endTag)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se encontraron datos válidos en la respuesta.")),
      );
      return;
    }

    final rawXml = response.substring(
      response.indexOf(startTag),
      response.indexOf(endTag) + endTag.length,
    );

    try {
      final document = XmlDocument.parse(rawXml);
      final tables = document.findAllElements('Table');
      List<Map<String, String>> parsedData = [];

      for (var table in tables) {
        parsedData.add({
          "nro_ruta": nroRuta,
          "Latitud": table.getElement('bscntlati')?.text ?? "N/A",
          "Longitud": table.getElement('bscntlogi')?.text ?? "N/A",
          "C.U": table.getElement('bscntCodf')?.text ?? "N/A",
          "C.F": table.getElement('bscocNcoc')?.text ?? "N/A",
        });
      }

      setState(() {
        _tablesData = parsedData;
      });

      _saveToDatabase(parsedData);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al procesar datos del servidor.")),
      );
    }
  }

  Future<void> _saveToDatabase(List<Map<String, String>> data) async {
    try {
      for (var item in data) {
        await _database.insert('rutast', {
          'nro_ruta': item['nro_ruta']!,
          'latitud': item['Latitud']!,
          'longitud': item['Longitud']!,
          'cu': item['C.U']!,
          'cf': item['C.F']!,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Datos guardados en la base de datos.')),
      );
    } catch (e) {
      print('Error al guardar datos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar datos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Importar Cortes"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20),
            TextField(
              controller: _codigoFijoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Código Ruta",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _sendData,
              child: Text("Importar Datos"),
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _tablesData.length,
                itemBuilder: (context, index) {
                  final table = _tablesData[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: table.entries.map((entry) {
                          return Text("${entry.key}: ${entry.value}");
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

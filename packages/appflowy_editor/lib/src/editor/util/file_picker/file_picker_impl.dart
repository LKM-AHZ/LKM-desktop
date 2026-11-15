import 'package:appflowy_editor/src/editor/util/file_picker/file_picker_service.dart';
import 'package:file_picker/file_picker.dart' as fp;

class FilePicker implements FilePickerService {
  @override
  Future<String?> getDirectoryPath({String? title}) {
    return fp.FilePicker.getDirectoryPath(dialogTitle: title);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    Function(fp.FilePickerStatus p1)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async {
    // file_picker 13.x: pickFiles returns List<PlatformFile>; when
    // [allowMultiple] is false only the first selection is used, matching
    // the previous FilePickerResult semantics.
    final files = await fp.FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
    );
    final chosen = allowMultiple ? files : files.take(1).toList();
    return FilePickerResult(chosen);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) {
    // file_picker 13.x requires the bytes to save; the editor never calls
    // this (export is handled by the host), so surface the gap clearly.
    throw UnimplementedError(
      'saveFile is unsupported with file_picker 13.x; supply bytes via '
      'FilePicker.saveFile in the host instead.',
    );
  }
}

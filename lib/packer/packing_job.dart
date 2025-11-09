import 'dart:io';

import 'atlas_models.dart';
import 'texture_packer.dart';

class PackingJob {
  const PackingJob({
    required this.inputPath,
    required this.outputPath,
    required this.settings,
  });

  final String inputPath;
  final String outputPath;
  final PackerSettings settings;
}

Future<PackingReport> executePacking(PackingJob job) {
  final packer = TexturePacker(job.settings);
  return packer.packDirectory(
    inputDir: Directory(job.inputPath),
    outputDir: Directory(job.outputPath),
  );
}

Future<PackingReport> runPackingJob(PackingJob job) => executePacking(job);

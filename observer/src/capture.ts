export async function captureScreen(): Promise<string> {
  const timestamp = Date.now();
  const placeholderPath = `/tmp/sentinel-screenshot-${timestamp}.png`;

  return placeholderPath;
}

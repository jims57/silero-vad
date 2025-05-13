import os
from pydub import AudioSegment

def split_wav_by_timestamps(input_wav_path, speech_timestamps, output_dir=None, output_prefix='en'):
    """
    Split a WAV file into multiple segments based on speech timestamps.
    
    Args:
        input_wav_path: Path to the input WAV file
        speech_timestamps: List of dictionaries with 'start' and 'end' timestamps in seconds
        output_dir: Directory to save the output files (defaults to same directory as input)
        output_prefix: Prefix for output filenames
    """
    # If no output directory specified, use the directory of the input file
    if output_dir is None:
        output_dir = os.path.dirname(input_wav_path)
    
    # Create the output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Load the audio file
    audio = AudioSegment.from_wav(input_wav_path)
    
    # Split audio based on timestamps
    for i, timestamp in enumerate(speech_timestamps):
        start_ms = int(timestamp['start'] * 1000)
        end_ms = int(timestamp['end'] * 1000)
        
        # Extract the segment
        segment = audio[start_ms:end_ms]
        
        # Save the segment
        output_filename = f"{output_prefix}-{i+1}.wav"
        output_path = os.path.join(output_dir, output_filename)
        segment.export(output_path, format="wav")
        
        print(f"Saved {output_filename}: {timestamp['start']}s to {timestamp['end']}s")
    
    return len(speech_timestamps)

if __name__ == "__main__":
    # Example usage
    from silero_vad import load_silero_vad, read_audio, get_speech_timestamps
    
    input_wav_path = '/content/en.wav'
    
    # Get speech timestamps
    model = load_silero_vad()
    wav = read_audio(input_wav_path)
    speech_timestamps = get_speech_timestamps(
        wav,
        model,
        return_seconds=True,
    )
    
    # Split the audio
    num_segments = split_wav_by_timestamps(input_wav_path, speech_timestamps)
    print(f"Split audio into {num_segments} segments")

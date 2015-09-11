//
//  Listener.m
//  Dino
//
//  Created by Lucy  on 9/10/15.
//  Copyright (c) 2015 Lucy. All rights reserved.
//

#import "Listener.h"
#import "libfft.h"
#define FFT_SIZE (8192)
#define FFT_EXP_SIZE (13)
#define SAMPLE_RATE (8000)
#define LOW_PASS_FILTER_PARAM (330)
#define MINIMUM (1000000000.0)

static char * NOTES[] = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };

//Creates window signal in order to reduce reading of frequencies that are not actually present
void buildHanWindow( float *window, int size )
{
    for( int i=0; i<size; ++i )
        window[i] = .5 * ( 1 - cos( 2 * M_PI * i / (size-1.0) ) );
}

//Multiplies audio input by window signal to reduce reading of frequencies that are not actually present
void applyWindow( float *window, float *data, int size )
{
    for( int i=0; i<size; ++i )
        data[i] *= window[i] ;
}

//Computes low pass parameters in order to filter out misleading higher frequencies
void computeSecondOrderLowPassParameters( float srate, float f, float *a, float *b )
{
    float a0;
    float w0 = 2 * M_PI * f/srate;
    float cosw0 = cos(w0);
    float sinw0 = sin(w0);
    //float alpha = sinw0/2;
    float alpha = sinw0/2 * sqrt(2);
    
    a0   = 1 + alpha;
    a[0] = (-2*cosw0) / a0;
    a[1] = (1 - alpha) / a0;
    b[0] = ((1-cosw0)/2) / a0;
    b[1] = ( 1-cosw0) / a0;
    b[2] = b[0];
}

//Applies the low pass filter to the audio to filter out misleading higher frequencies
float processSecondOrderFilter( float x, float *mem, float *a, float *b )
{
    float ret = b[0] * x + b[1] * mem[0] + b[2] * mem[1]
    - a[0] * mem[2] - a[1] * mem[3] ;
    mem[1] = mem[0];
    mem[0] = x;
    mem[3] = mem[2];
    mem[2] = ret;
    
    return ret;
    
}

//Initialize values in frequency and note tables
void initTables(float * mem1, float * mem2, float * freqTable, char** noteNameTable, float * notePitchTable){
    mem1[0] = 0; mem1[1] = 0; mem1[2] = 0; mem1[3] = 0;
    mem2[0] = 0; mem2[1] = 0; mem2[2] = 0; mem2[3] = 0;
    
    for( int i=0; i<FFT_SIZE; ++i ) {
        freqTable[i] = ( SAMPLE_RATE * i ) / (float) ( FFT_SIZE );
    }
    for( int i=0; i<FFT_SIZE; ++i ) {
        noteNameTable[i] = NULL;
        notePitchTable[i] = -1;
    }
    for( int i=0; i<127; ++i ) {
        float pitch = ( 440.0 / 32.0 ) * pow( 2, (i-9.0)/12.0 ) ;
        if( pitch > SAMPLE_RATE / 2.0 )
            break;
        //find the closest frequency using brute force.
        float min = MINIMUM;
        int index = -1;
        for( int j=0; j<FFT_SIZE; ++j ) {
            if( fabsf( freqTable[j]-pitch ) < min ) {
                min = fabsf( freqTable[j]-pitch );
                index = j;
            }
        }
        noteNameTable[index] = NOTES[i% NUMNOTES];
        notePitchTable[index] = pitch;
    }
}

//Initializes PortAudio, which is what is used to gather input/pitches from the microphone.
//Returns 0 if initialization is successful; otherwise, returns 1
void initPortAudio(PaError * err, PaStreamParameters * inputParametersp, PaStream ** stream){
    *err = Pa_Initialize();
    if( *err != paNoError ) return;
    
    inputParametersp->device = Pa_GetDefaultInputDevice();
    inputParametersp->channelCount = 1;
    inputParametersp->sampleFormat = paFloat32;
    inputParametersp->suggestedLatency = Pa_GetDeviceInfo( inputParametersp->device )->defaultHighInputLatency ;
    inputParametersp->hostApiSpecificStreamInfo = NULL;
    
    printf( "Opening %s\n",
           Pa_GetDeviceInfo( inputParametersp->device )->name );
    
    *err = Pa_OpenStream( stream,
                         inputParametersp,
                         NULL, //no output
                         SAMPLE_RATE,
                         FFT_SIZE,
                         paClipOff,
                         NULL,
                         NULL );
    if( *err != paNoError ) return;
    
    *err = Pa_StartStream( *stream );
}

@implementation Listener
- (Listener*)init
{
    self = [super init];
    if (self) {
        buildHanWindow( window, FFT_SIZE );
        fft = initfft( FFT_EXP_SIZE );
        computeSecondOrderLowPassParameters( SAMPLE_RATE, LOW_PASS_FILTER_PARAM, a, b );
        initTables(mem1, mem2, freqTable, noteNameTable, notePitchTable);
        initPortAudio(&err, &inputParameters, &stream);
        self.info = [[ListenScore alloc] init];
    }
    return self;
}

@end

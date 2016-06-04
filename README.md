# LBAudioDetective

## About
LBAudioDetective is part of my Matura project to graduate from school. It's somewhat similar to Shazam. It is able to compare two audio signals based on their content. Of course, the reliability is not nearly as good as Shazam's. I'm not planning to continue working on this project in the near future, however, contributions are always welcome.
If you're interested in the underlying technologies and algorithms used to implement this project, check out the essay I wrote on it. It explains how LBAudioDetective was developed and how it was used to write an iOS app that identifies birds by their songs.

## Usage
LBAudioDetective is a C library that consists of three different classes, one of which is private. 
Although it provides several options and functions to compute an audio fingerprint, the easiest way to compare two audio files is as follows:

```objc
LBAudioDetectiveRef detective = LBAudioDetectiveNew();
Float32 match = 0.0f;
LBAudioDetectiveCompareAudioURLs(detective, firstURL, secondURL, 0, &match);
NSLog(@"The files are equal to a percentage of %f", match);
LBAudioDetectiveDispose(detective);
```

## Requirements
LBAudioDetective is only compatible with iOS and doesn't support Mac OS X. It could be ported of course but I couldn't find the time to do so.
The library links against the following frameworks: AVFoundation, AudioUnit, Accelerate, AudioToolbox and Foundation of course.

## License
LBAudioDetective is licensed under the [MIT License](http://opensource.org/licenses/mit-license.php).

## Contact
If you have any questions, I'd be happy to answer them. You can also [follow me on Twitter](https://twitter.com/lbrndnr) of course :)
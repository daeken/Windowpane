function synth(events, duration) {
	var samples = new Float32Array(22050), i=0, channels = {}, a = new Audio;
	for each(e in events) {
		while(i < e[0]*44100) {
			samples[i++] = Math.sin(2 * Math.PI * 440 / 44100 * i);
		}
		switch(e[1]) {
			case 0:
				alert('done!' + i)
		}
	}
	i = 0;
	a.mozSetup(1, 44100);
	setInterval(
		function() {
			if()
		}, 
		500
	)
}

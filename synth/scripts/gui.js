$(document).ready(function() {
	$('#play').click(function() {
		events = [
			[0, 1], 
			[2, 2], 
		];
		synth(events, 10);
	});
})

extends GutTest

## NetLossEstimator coverage (split out of test_net_internet.gd for the 400-line rule).

func test_loss_estimator_reports_zero_on_a_complete_snapshot_sequence() -> void:
	var loss: NetLossEstimator = NetLossEstimator.new(NetTuning.SNAPSHOT_INTERVAL)
	for step: int in range(10):
		loss.observe(1, step * NetTuning.SNAPSHOT_INTERVAL, float(step) * 0.05)
	assert_almost_eq(loss.loss(0.5), 0.0, 0.0001)

func test_loss_estimator_measures_snapshot_sequence_gaps() -> void:
	var loss: NetLossEstimator = NetLossEstimator.new(NetTuning.SNAPSHOT_INTERVAL)
	# Nine expected snapshot ticks, every other one lost in transit.
	for step: int in range(10):
		if step % 2 == 0:
			loss.observe(1, step * NetTuning.SNAPSHOT_INTERVAL, float(step) * 0.05)
	assert_almost_eq(loss.loss(0.5), 1.0 - 5.0 / 9.0, 0.001)

func test_loss_estimator_ignores_repeated_chunks_and_forgets_old_samples() -> void:
	var loss: NetLossEstimator = NetLossEstimator.new(NetTuning.SNAPSHOT_INTERVAL)
	for step: int in range(6):
		# A chunked snapshot delivers the same tick more than once.
		loss.observe(1, step * NetTuning.SNAPSHOT_INTERVAL, float(step) * 0.05)
		loss.observe(1, step * NetTuning.SNAPSHOT_INTERVAL, float(step) * 0.05)
	assert_eq(loss.loss(0.3), 0.0)
	assert_eq(loss.loss(NetLossEstimator.WINDOW_SECONDS + 10.0), 0.0)

func test_loss_estimator_reports_the_worst_peer_and_forgets_removed_ones() -> void:
	var loss: NetLossEstimator = NetLossEstimator.new(1)
	for tick: int in range(9):
		loss.observe(1, tick, float(tick) * 0.05)
		if tick % 3 == 0:
			loss.observe(2, tick, float(tick) * 0.05)
	assert_almost_eq(loss.loss(0.5), 1.0 - 3.0 / 7.0, 0.001)
	loss.remove(2)
	assert_almost_eq(loss.loss(0.5), 0.0, 0.0001)

func test_loss_estimator_batch_tick_reads_the_packets_newest_frame() -> void:
	assert_eq(NetLossEstimator.batch_tick({"frames": [{"tick": 5}, {"tick": 7}]}), 7)
	assert_eq(NetLossEstimator.batch_tick({"tick": 3}), 3)
	assert_eq(NetLossEstimator.batch_tick({"frames": []}), -1)
	assert_eq(NetLossEstimator.batch_tick({}), -1)

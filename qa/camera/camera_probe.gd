extends SceneTree

func _initialize() -> void:
    print("CAMERA_SCAN_TEST_START")
    CameraServer.set_monitoring_feeds(true)
    await create_timer(3.0).timeout
    CameraServer.set_monitoring_feeds(false)
    print("CAMERA_SCAN_TEST_END")
    quit(0)

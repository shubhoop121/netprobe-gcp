def test_stats_endpoint(client):
    """
    Tests the /api/v1/stats endpoint.
    Confirms it returns a 200 OK and the correct JSON structure .
    """
    # Make a GET request to the endpoint
    response = client.get('/api/v1/stats')

    # 1. Check that the request was successful
    assert response.status_code == 200

    # 2. Check that the response is JSON
    assert response.content_type == 'application/json'

    # 3. Check that the JSON data has the keys we expect
    data = response.json
    assert 'total_connections' in data
    assert 'total_alerts' in data
    assert 'ips_blocked_now' in data
    assert 'devices_tracked' in data

    # 4. Check that the values are numbers (or 0)
    assert isinstance(data['total_connections'], int)
    assert isinstance(data['total_alerts'], int)
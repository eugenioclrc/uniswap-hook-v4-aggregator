// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract ChainlinkFeedMock {
    uint8 private _decimals;
    int256 private _value;

    constructor(uint8 _d) {
        _decimals = _d;
    }

    function setValue(int256 answer) external {
        // Logic to set the value, e.g., for testing purposes
        // This is a mock, so it doesn't interact with any real data source
        _value = answer;
    }

    // Mock implementation of Chainlink Feed
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _value, block.timestamp, block.timestamp, 1);
    }

    // fixed decimals
    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

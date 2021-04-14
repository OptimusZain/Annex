pragma solidity ^0.6.12;

interface IComptroller {
	function refreshVenusSpeeds() external;
}

contract RefreshSpeedsProxy {
	constructor(address comptroller) public {
		IComptroller(comptroller).refreshVenusSpeeds();
	}
}

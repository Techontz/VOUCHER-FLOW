<?php

use App\Http\Controllers\Api\Erp\Fleet;
use Illuminate\Support\Facades\Route;

/*
 * Fleet & transport, under /api/erp/fleet. Reads need fleet.view; drivers
 * reach their own trips only, through my-trips with fleet.own.
 */
Route::prefix('fleet')->middleware('module:fleet')->group(function () {
    Route::middleware('permission:fleet.view')->group(function () {
        Route::get('overview', [Fleet\FleetController::class, 'overview']);
        Route::get('lookups', [Fleet\FleetController::class, 'lookups']);
        Route::get('reports/profitability', [Fleet\FleetController::class, 'profitability']);

        Route::get('vehicles', [Fleet\VehicleController::class, 'index']);
        Route::get('vehicles/{vehicle}', [Fleet\VehicleController::class, 'show']);
        Route::get('drivers', [Fleet\DriverController::class, 'index']);
        Route::get('drivers/{driver}', [Fleet\DriverController::class, 'show']);
        Route::get('standards', [Fleet\FuelStandardController::class, 'index']);

        Route::get('trips', [Fleet\TripController::class, 'index']);
        Route::get('trips/{trip}', [Fleet\TripController::class, 'show']);
        Route::get('fuel', [Fleet\TripController::class, 'fuelLog']);

        Route::get('schedules', [Fleet\MaintenanceController::class, 'schedules']);
        Route::get('services', [Fleet\MaintenanceController::class, 'services']);
        Route::get('services/{service}', [Fleet\MaintenanceController::class, 'showService']);
        Route::get('tyres', [Fleet\MaintenanceController::class, 'tyres']);
        Route::get('downtimes', [Fleet\MaintenanceController::class, 'downtimes']);
    });

    Route::middleware('permission:fleet.manage')->group(function () {
        Route::post('vehicles', [Fleet\VehicleController::class, 'store']);
        Route::put('vehicles/{vehicle}', [Fleet\VehicleController::class, 'update']);
        Route::post('vehicles/{vehicle}/status', [Fleet\VehicleController::class, 'status']);
        Route::get('driver-candidates', [Fleet\DriverController::class, 'candidates']);
        Route::post('drivers', [Fleet\DriverController::class, 'store']);
        Route::put('drivers/{driver}', [Fleet\DriverController::class, 'update']);
        Route::post('standards', [Fleet\FuelStandardController::class, 'store']);
        Route::put('standards/{standard}', [Fleet\FuelStandardController::class, 'update']);
        Route::delete('standards/{standard}', [Fleet\FuelStandardController::class, 'destroy']);
    });

    Route::middleware('permission:fleet.trips')->group(function () {
        Route::post('trips', [Fleet\TripController::class, 'store']);
        Route::put('trips/{trip}', [Fleet\TripController::class, 'update']);
        Route::post('trips/{trip}/dispatch', [Fleet\TripController::class, 'dispatchTrip']);
        Route::post('trips/{trip}/complete', [Fleet\TripController::class, 'complete']);
        // Over the fuel standard, closing also needs fleet.approve: checked in the service.
        Route::post('trips/{trip}/close', [Fleet\TripController::class, 'close']);
        Route::post('trips/{trip}/cancel', [Fleet\TripController::class, 'cancel']);
    });

    Route::post('trips/{trip}/fuel', [Fleet\TripController::class, 'storeFuel'])->middleware('permission:fleet.fuel');
    Route::post('trips/{trip}/expenses', [Fleet\TripController::class, 'storeExpense'])->middleware('permission:fleet.expenses');

    Route::middleware('permission:fleet.approve')->group(function () {
        Route::get('pending', [Fleet\TripController::class, 'pending']);
        Route::post('fuel/{fuel}/decision', [Fleet\TripController::class, 'decideFuel']);
        Route::post('expenses/{expense}/decision', [Fleet\TripController::class, 'decideExpense']);
    });

    Route::middleware('permission:fleet.maintenance')->group(function () {
        Route::post('schedules', [Fleet\MaintenanceController::class, 'storeSchedule']);
        Route::put('schedules/{schedule}', [Fleet\MaintenanceController::class, 'updateSchedule']);
        Route::delete('schedules/{schedule}', [Fleet\MaintenanceController::class, 'destroySchedule']);
        Route::post('services', [Fleet\MaintenanceController::class, 'storeService']);
        Route::put('services/{service}', [Fleet\MaintenanceController::class, 'updateService']);
        Route::post('services/{service}/post', [Fleet\MaintenanceController::class, 'postService']);
        Route::post('services/{service}/cancel', [Fleet\MaintenanceController::class, 'cancelService']);
        Route::post('tyres', [Fleet\MaintenanceController::class, 'storeTyre']);
        Route::post('tyres/{tyre}/remove', [Fleet\MaintenanceController::class, 'removeTyre']);
        Route::post('downtimes', [Fleet\MaintenanceController::class, 'storeDowntime']);
        Route::post('downtimes/{downtime}/end', [Fleet\MaintenanceController::class, 'endDowntime']);
    });

    // Drivers: their own trips, and nothing else.
    Route::middleware('permission:fleet.own')->group(function () {
        Route::get('my-trips', [Fleet\TripController::class, 'myIndex']);
        Route::get('my-trips/lookups', [Fleet\FleetController::class, 'myLookups']);
        Route::get('my-trips/{trip}', [Fleet\TripController::class, 'myShow'])->whereNumber('trip');
        Route::post('my-trips/{trip}/fuel', [Fleet\TripController::class, 'myStoreFuel'])->whereNumber('trip');
        Route::post('my-trips/{trip}/expenses', [Fleet\TripController::class, 'myStoreExpense'])->whereNumber('trip');
    });
});

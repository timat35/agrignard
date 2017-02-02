/**
* Name: JSON File Loading
* Author:  Arnaud Grignard
* Description: Initialize a grid from a JSON FIle. 
* Tags:  load_file, grid, json
*/

model json_loading

import "CityGamatrix.gaml"

global {
    int nb_pev <- 10 parameter: "Number of PEVs:" category: "Environment";
    list< map<string, unknown> > job_queue <- [];
    file prob <- text_file("../includes/demand.txt");
	list<float> prob_array <- [];
	int max_building_density <- 30;
	int people_per_floor <- 10;
	int total_population <- 0;
	float step <- 1 # second;
	int current_second update: (time / # second) mod 86400;
	list<int> density_array; // <- c["objects"]["density"];
	int max_density <- max(density_array);
	float max_prob;
	int job_interval <- 10;
	int graph_interval <- 1000;
	
	int maximumJobCount <- 10 parameter: "Max Job Count:" category: "Environment";
	int max_wait_time <- 15 parameter: "Max Wait Time (minutes):" category: "Environment";
	
	int missed_jobs <- 0;
	int completed_jobs <- 0;
	int total_jobs <- 0;
	
	int traffic_interval <- 60 * 60 # cycles;
	float max_traffic_count <- 1500.0 * traffic_interval / 3600 * nb_pev / 10;
	
	bool do_traffic_visualization;
	
	matrix traffic <- 0 as_matrix({ matrix_size, matrix_size });
	
	// TODO: Find better metric for these values above.
	// TODO: Are all of these variables INPUTS into the simulation? Down the road, these can certainly result in different "configurations."
   
	init {
		
		starting_date <- date([2017,1,1,0,0,0]);
		
		filename <- '../includes/mobility_configurations/diagonal.json';
 
		do initGrid;
        
        loop r from: 0 to: length(prob) - 1
		{
			add (float(prob[r]) * maximumJobCount / 60) to: prob_array;
		}
		
		max_prob <- max(prob_array);
        	
    	create pev number: nb_pev {
    	  	location <- one_of(cityMatrix where (each.type = 6)).location; // + {rnd(-2.0,2.0),rnd(-2.0,2.0)};
    	  	color <- # white;
    	  	speed <- 0.3;
    	  	// TODO: Determine correct speed.
    	  	status <- "wander";
    	 }
        
         ask pev {
        	do findNewTarget;
         }
	}
	
	reflex traffic_count when: do_traffic_visualization {
		ask cityMatrix where (each.type = 6) {
			// Figure out how to get x and y coordinates of each cell.
			traffic[grid_x , grid_y] <- int(traffic[grid_x , grid_y]) + length(agents_inside(self));
		}
	}
	
	reflex traffic_draw when: every(traffic_interval # cycles) and do_traffic_visualization {
		// From http://stackoverflow.com/questions/20792445/calculate-rgb-value-for-a-range-of-values-to-create-heat-map.
		ask cityMatrix where (each.type = 6) {
			float minimum <- 0.0;
			int recent_traffic <- int(traffic[grid_x , grid_y]);
			float ratio <- 2 * (float(recent_traffic) - minimum) / (max_traffic_count - minimum);
	    	int b <- int(max([0, 255*(1 - ratio)]));
	    	int r <- int(max([0, 255*(ratio - 1)]));
	    	int g <- 255 - b - r;
	    	color <- rgb(r, g, b);
			traffic[grid_x , grid_y] <- 0;
		}
	}
	
	action findLocation(map<string, float> result) {
		int random_density <- rnd(1, max_density - 1);
		list<cityMatrix> the_cells <- cityMatrix where (each.density > random_density);
		loop while: length(cells) = 0 {
			random_density <- rnd(1, max_density - 1);
		}
		bool found <- false;
		cityMatrix cell <- one_of(the_cells);
		list<cityMatrix> neighbors;
		int i <- 0;
		loop while: (found = false) {
			neighbors <- cell neighbors_at i where (each.type = 6);
			found <- length(neighbors) != 0;
			i <- i + 1;
			if (i > matrix_size / 3) {
				break;
			}
		}
		if (found) {
			point road_cell <- one_of(neighbors).location;
			result['x'] <- float(road_cell.x);
			result['y'] <- float(road_cell.y);
			return;
		} else {
			point road_cell <- one_of(cityMatrix where (each.type = 6)).location;
			result['x'] <- float(road_cell.x);
			result['y'] <- float(road_cell.y);
			return;
		}
	}
	
	reflex job_manage when: every(job_interval # cycles)
	{
		
		if (time > # day and ! looping) {
			do pause;
		}
		
		// Manage any missed jobs.
		
		loop job over: job_queue where (current_second - int(each['start']) > max_wait_time) {
			missed_jobs <- missed_jobs + 1;
			total_jobs <- total_jobs + 1;
			remove job from: job_queue;
		}
		
		// Add new jobs.
		
		float p <- prob_array[current_second];
		float r <- rnd(0, max_prob);
		if (r <= p)
		{
			int job_count;
			if (floor(r * job_interval) = 0)
			{
				job_count <- flip(r * job_interval) ? 1 : 0;
			} else
			{
				job_count <- int(floor(r * job_interval));
			}
			if (job_count > 0)
			{
				loop i from: 0 to: job_count - 1 {
					map<string, unknown> m;
					m['start'] <- current_second;
					map<string, float> pickup;
					do findLocation(pickup);
					m['pickup.x'] <- float(pickup['x']);
					m['pickup.y'] <- float(pickup['y']);
					map<string, float> dropoff;
					do findLocation(dropoff);
					m['dropoff.x'] <- float(dropoff['x']);
					m['dropoff.y'] <- float(dropoff['y']);
					add m to: job_queue;
				}
			} 
		}
		
		//write string(total_jobs) + ", " + string(completed_jobs) + ", " + string(missed_jobs) color: # black;

	}
}

species pev skills: [moving] {
	point target;
	rgb color;
	string status;
	map<string, unknown> pev_job;
	
	aspect base {
		draw circle(1.5) at: location color: color;
	}
	
	action findNewTarget {
		if (status = 'wander') {
			if (length(job_queue) > 0) {
				map<string, unknown> job <- job_queue[0];
				remove job from: job_queue;
				pev_job <- job;
				status <- 'pickup';
				float p_x <- float(job['pickup.x']);
				float p_y <- float(job['pickup.y']);
				target <- { p_x, p_y, 0.0};
				color <- # green;
			} else {
				status <- 'wander';
				target <- one_of(cityMatrix where (each.type = 6 and each.location distance_to self >= matrix_size / 2)).location;
				color <- # white;
			}
		} else if (status = 'pickup') {
			status <- 'dropoff';
			float d_x <- float(pev_job['dropoff.x']);
			float d_y <- float(pev_job['dropoff.y']);
			target <- { d_x, d_y, 0.0};
			color <- # red;
		} else if (status = 'dropoff') {
			completed_jobs <- completed_jobs + 1;
			total_jobs <- total_jobs + 1;
			status <- 'wander';
			target <- one_of(cityMatrix where (each.type = 6 and each.location distance_to self >= matrix_size / 2)).location;
			color <- # white;
		}
	}
	
	reflex move {
		do goto target: target on: cityMatrix where (each.type = 6) speed: speed;
		if (target = location) {
			do findNewTarget;
		} else if (status = 'wander') {
			if (length(job_queue) > 0) {
				map<string, unknown> job <- job_queue[0];
				remove job from: job_queue;
				pev_job <- job;
				status <- 'pickup';
				float p_x <- float(job['pickup.x']);
				float p_y <- float(job['pickup.y']);
				target <- { p_x, p_y, 0.0};
				color <- # green;
			}
		}
	}
}

experiment Display  type: gui {
	parameter "Heat Map:" var: do_traffic_visualization <- true category: "Grid";
	output {
		display cityMatrixView   type:opengl background:#black {	
			species cityMatrix aspect:base;
			species pev aspect:base;	
		}
		
		/*display job_chart refresh: every(graph_interval # cycles) {
			chart "Job Rate" type: series {
				data "Completion Rate" value: completed_jobs / (total_jobs = 0 ? 1 : total_jobs) color: # green;
			}
		}*/
		
		/*display prob_chart refresh: every(10 # cycles) {
			chart "Probability" type: series {
				data "Demand Value" value: prob_array[current_second] color: # blue;
			}
		}*/
		
		monitor Time value:string(current_date.hour) + ":" + (current_date.minute < 10 ? "0" + string(current_date.minute) : string(current_date.minute)) refresh:every(1 # minute);
		monitor Completion value: string((completed_jobs / (total_jobs = 0 ? 1 : total_jobs) * 100) with_precision 1) + "%" refresh: every(1 # minute);
		monitor Total value:total_jobs;
	}
}

experiment Display_Light type: gui {
	parameter "Heat Map:" var: do_traffic_visualization <- false category: "Grid";
	output {
		monitor Time value:string(current_date.hour) + ":" + (current_date.minute < 10 ? "0" + string(current_date.minute) : string(current_date.minute)) refresh:every(1 # minute);
		monitor Completion value: string((completed_jobs / (total_jobs = 0 ? 1 : total_jobs) * 100) with_precision 1) + "%" refresh: every(1 # minute);
		monitor Total value:total_jobs;
	}
}
